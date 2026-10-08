import Foundation

// Crashlytics quirk: events carry no binary-image UUIDs, so a dSYM can only be matched to a
// frame's library by name, never to the build that crashed — hence the per-dSYM warning.
struct DSYMSymbolicator: FrameSymbolizer {
    private let fileStore: FileStore
    private let subprocessExecutor: SubprocessExecutor

    init(fileStore: FileStore, subprocessExecutor: SubprocessExecutor) {
        self.fileStore = fileStore
        self.subprocessExecutor = subprocessExecutor
    }

    private struct Binary {
        var name: String
        var dwarfPath: String
        var bundlePath: String
    }

    private struct TextSegment {
        var textVMAddr: UInt64
        var uuid: String?
    }

    static let xcrun = "/usr/bin/xcrun"
    static let arch = "arm64"

    /// Locations per normalized library name, then per unslid frame address.
    private typealias ResolvedLocations = [String: [UInt64: AtosLocation]]

    // MARK: - FrameSymbolizer

    func symbolicate(_ events: [CrashlyticsEvent], dsymPaths paths: [String]) -> SymbolicationResult {
        guard !paths.isEmpty else { return SymbolicationResult(events: events, warnings: []) }
        var warnings: [CommandWarning] = []
        let binaries = discoverBinaries(in: paths, warnings: &warnings)
        let addresses = Self.addressesByLibrary(in: events, binaries: binaries)
        let resolved = resolveLocations(of: addresses, using: binaries, warnings: &warnings)
        guard !resolved.isEmpty else { return SymbolicationResult(events: events, warnings: warnings) }
        return SymbolicationResult(events: events.map { Self.apply(resolved, to: $0) }, warnings: warnings)
    }

    private func resolveLocations(
        of addresses: [String: Set<UInt64>], using binaries: [Binary], warnings: inout [CommandWarning]
    ) -> ResolvedLocations {
        var resolved: ResolvedLocations = [:]
        for binary in binaries {
            let library = Self.normalized(binary.name)
            guard let wanted = addresses[library], resolved[library] == nil else { continue }
            guard let segment = textSegment(of: binary, warnings: &warnings),
                  let locations = atos(binary, segment: segment, addresses: wanted.sorted(), warnings: &warnings)
            else { continue }
            resolved[library] = locations
            warnings.append(Self.unverifiedWarning(for: binary, segment: segment))
        }
        return resolved
    }

    private static func unverifiedWarning(for binary: Binary, segment: TextSegment) -> CommandWarning {
        let uuidNote = segment.uuid.map { " (UUID \($0))" } ?? ""
        return CommandWarning(
            code: .dsymUnverified,
            message: "\(binary.name) was symbolicated with a dSYM\(uuidNote)"
                + "; Crashlytics events carry no binary image UUIDs, so this dSYM cannot be matched to the build that "
                + "crashed. Treat the symbols as correct only if the dSYM comes from the same build as the event.",
            path: binary.bundlePath)
    }

    // MARK: - dSYM discovery

    // `__MACOSX` holds copies zip archives carry; ignore them.
    private func discoverBinaries(in paths: [String], warnings: inout [CommandWarning]) -> [Binary] {
        var binaries: [Binary] = []
        var seen = Set<String>()
        for path in paths {
            let files = (try? fileStore.listFiles(
                under: path, withExtensions: [""], skippingDirectories: ["__MACOSX"])) ?? []
            let found = files.compactMap(Self.binary(atPath:))
            if found.isEmpty {
                warnings.append(CommandWarning(
                    code: .dsymFailed, message: "no dSYM bundle with a DWARF binary found under \(path).", path: path))
            }
            for binary in found where seen.insert(binary.dwarfPath).inserted {
                binaries.append(binary)
            }
        }
        return binaries
    }

    private static func binary(atPath path: String) -> Binary? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 5, !components.contains("__MACOSX") else { return nil }
        let end = components.count
        guard components[end - 2] == "DWARF", components[end - 3] == "Resources", components[end - 4] == "Contents",
              components[end - 5].lowercased().hasSuffix(".dsym")
        else { return nil }
        let bundle = (path.hasPrefix("/") ? "/" : "") + components[0..<(end - 4)].joined(separator: "/")
        return Binary(name: components[end - 1], dwarfPath: path, bundlePath: bundle)
    }

    // MARK: - Frame addresses

    /// Case-insensitive, without a bundle or dylib suffix.
    static func normalized(_ library: String) -> String {
        var name = library.lowercased()
        for suffix in [".framework", ".dylib", ".appex", ".app"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }

    private static func addressesByLibrary(in events: [CrashlyticsEvent], binaries: [Binary]) -> [String: Set<UInt64>] {
        let names = Set(binaries.map { normalized($0.name) })
        var addresses: [String: Set<UInt64>] = [:]
        for event in events {
            forEachFrame(of: event) { frame in
                guard let address = frame.address, let library = FrameClassifier.knownLibrary(frame.library),
                      names.contains(normalized(library))
                else { return }
                addresses[normalized(library), default: []].insert(address)
            }
        }
        return addresses
    }

    private static func forEachFrame(of event: CrashlyticsEvent, _ body: (CrashlyticsFrame) -> Void) {
        if let blame = event.blameFrame { body(blame) }
        event.threads.forEach { $0.frames.forEach(body) }
        event.exceptions.forEach { $0.frames.forEach(body) }
        event.errors.forEach { $0.frames.forEach(body) }
    }

    // MARK: - otool and atos

    private func textSegment(of binary: Binary, warnings: inout [CommandWarning]) -> TextSegment? {
        let arguments = ["otool", "-arch", Self.arch, "-l", binary.dwarfPath]
        let result: SubprocessResult
        do {
            result = try subprocessExecutor.execute(executable: Self.xcrun, arguments: arguments, standardInput: nil)
        } catch {
            let message = "could not run otool on \(binary.dwarfPath): \(error.localizedDescription)"
            warnings.append(Self.failure(message, binary))
            return nil
        }
        guard result.exitCode == 0, let vmaddr = Self.textVMAddr(in: result.standardOutput) else {
            let reason = result.standardError.trimmedNonEmpty ?? "no __TEXT segment in the \(Self.arch) slice"
            warnings.append(Self.failure("otool could not read \(binary.dwarfPath): \(reason)", binary))
            return nil
        }
        return TextSegment(textVMAddr: vmaddr, uuid: Self.uuid(in: result.standardOutput))
    }

    private func atos(
        _ binary: Binary, segment: TextSegment, addresses: [UInt64], warnings: inout [CommandWarning]
    ) -> [UInt64: AtosLocation]? {
        let arguments = Self.atosArguments(for: binary, segment: segment, addresses: addresses)
        let result: SubprocessResult
        do {
            result = try subprocessExecutor.execute(executable: Self.xcrun, arguments: arguments, standardInput: nil)
        } catch {
            let message = "could not run atos for \(binary.name): \(error.localizedDescription)"
            warnings.append(Self.failure(message, binary))
            return nil
        }
        let lines = Self.outputLines(of: result.standardOutput)
        guard result.exitCode == 0, lines.count == addresses.count else {
            let reason = result.standardError.trimmedNonEmpty
                ?? Self.unexplainedAtosFailure(result, lineCount: lines.count, addressCount: addresses.count)
            warnings.append(Self.failure("atos failed for \(binary.name): \(reason)", binary))
            return nil
        }
        var locations: [UInt64: AtosLocation] = [:]
        for (address, line) in zip(addresses, lines) {
            if let location = AtosLocation(line: line) { locations[address] = location }
        }
        return locations
    }

    private static func atosArguments(for binary: Binary, segment: TextSegment, addresses: [UInt64]) -> [String] {
        func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
        let loadAddress = segment.textVMAddr
        return ["atos", "-arch", arch, "-o", binary.dwarfPath, "-l", hex(loadAddress)]
            + addresses.map { hex(loadAddress + $0) }
    }

    // atos ends its output with a newline; that trailing blank is not a result.
    private static func outputLines(of output: String) -> [String] {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func unexplainedAtosFailure(
        _ result: SubprocessResult, lineCount: Int, addressCount: Int
    ) -> String {
        result.exitCode == 0 ? "\(lineCount) results for \(addressCount) addresses" : "exit code \(result.exitCode)"
    }

    private static func failure(_ message: String, _ binary: Binary) -> CommandWarning {
        CommandWarning(code: .dsymFailed, message: message, path: binary.bundlePath)
    }

    // Sections repeat `segname __TEXT` but carry `addr`, so only a segment command's own `vmaddr` counts.
    static func textVMAddr(in otool: String) -> UInt64? {
        var segment: String?
        for raw in otool.split(separator: "\n") {
            let words = raw.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count >= 2 else { continue }
            switch words[0] {
            case "segname": segment = String(words[1])
            case "vmaddr" where segment == "__TEXT": return UInt64(words[1].dropFirst(2), radix: 16)
            default: break
            }
        }
        return nil
    }

    static func uuid(in otool: String) -> String? {
        for raw in otool.split(separator: "\n") {
            let words = raw.split(separator: " ", omittingEmptySubsequences: true)
            if words.count == 2, words[0] == "uuid" { return String(words[1]) }
        }
        return nil
    }

    // MARK: - Applying locations to events

    private static func apply(_ resolved: ResolvedLocations, to event: CrashlyticsEvent) -> CrashlyticsEvent {
        var copy = event
        copy.blameFrame = copy.blameFrame.map { apply(resolved, to: $0) }
        copy.threads = copy.threads.map { thread in
            var thread = thread
            thread.frames = thread.frames.map { apply(resolved, to: $0) }
            return thread
        }
        copy.exceptions = copy.exceptions.map { apply(resolved, to: $0) }
        copy.errors = copy.errors.map { apply(resolved, to: $0) }
        return copy
    }

    private static func apply(
        _ resolved: ResolvedLocations, to exception: CrashlyticsException
    ) -> CrashlyticsException {
        var copy = exception
        copy.frames = copy.frames.map { apply(resolved, to: $0) }
        return copy
    }

    private static func apply(_ resolved: ResolvedLocations, to frame: CrashlyticsFrame) -> CrashlyticsFrame {
        guard let address = frame.address, let library = FrameClassifier.knownLibrary(frame.library),
              let location = resolved[normalized(library)]?[address]
        else { return frame }
        var copy = frame
        copy.firebaseSymbol = frame.symbol
        copy.symbol = location.symbol
        copy.file = location.file
        copy.line = location.line
        copy.symbolicated = "dsym"
        return copy
    }
}
