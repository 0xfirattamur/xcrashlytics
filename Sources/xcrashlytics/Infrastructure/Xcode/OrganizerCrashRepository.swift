import Foundation

struct OrganizerCrashRepository: XcodeCrashRepository {
    private let fileStore: FileStore
    private let homeDirectory: String
    private let scanner: XcodeCrashScanner
    private let parsers: CrashReportParserRegistry

    init(fileStore: FileStore, homeDirectory: String) {
        self.fileStore = fileStore
        self.homeDirectory = homeDirectory
        self.scanner = XcodeCrashScanner(fileStore: fileStore)
        self.parsers = CrashReportParserRegistry(fileStore: fileStore)
    }

    /// Two-component prefixes are organizations, not apps, and are skipped.
    static func organizerDirectories(bundleId: String, homeDirectory: String) -> [String] {
        let parts = bundleId.split(separator: ".")
        guard !parts.isEmpty else { return [] }
        return stride(from: parts.count, through: min(parts.count, 3), by: -1).map { count in
            "\(homeDirectory)/Library/Developer/Xcode/Products/\(parts.prefix(count).joined(separator: "."))"
        }
    }

    // Xcode files app-extension reports under the containing app. That directory also
    // holds sibling apps and extensions, so only exact bundle-id matches are kept there.
    func organizerCrashes(bundleId: String) -> XcodeCrashLoadResult {
        let directories = Self.organizerDirectories(bundleId: bundleId, homeDirectory: homeDirectory)
        let load = crashes(in: directories)
        let ownDirectory = directories.first.map { $0 + "/" }
        let crashes = load.crashes.filter { crash in
            ownDirectory.map(crash.filePath.hasPrefix) == true
                || crash.event.bundleId?.caseInsensitiveCompare(bundleId) == .orderedSame
        }
        return XcodeCrashLoadResult(crashes: crashes, warnings: load.warnings)
    }

    func crashes(in directories: [String]) -> XcodeCrashLoadResult {
        let scan = scanner.scan(directories: directories)
        var crashes: [XcodeCrash] = []
        var warnings = scan.warnings

        for path in scan.paths {
            do {
                let parsed = try parsers.parse(path: path)
                warnings.append(contentsOf: parsed.warnings)
                crashes.append(makeCrash(from: parsed.event, path: path))
            } catch {
                warnings.append(Self.warning(for: error, path: path))
            }
        }

        crashes = Self.dedupedByIncident(crashes)
        // The id tie-break keeps order stable when two incidents share an mtime.
        crashes.sort { ($0.fileMtime, $0.event.id) > ($1.fileMtime, $1.event.id) }
        return XcodeCrashLoadResult(crashes: crashes, warnings: warnings)
    }

    // MARK: - Helpers

    private func makeCrash(from event: CrashEvent, path: String) -> XcodeCrash {
        let attributes = (try? fileStore.attributes(at: path))
            ?? FileAttributes(size: 0, modificationDate: Date(timeIntervalSince1970: 0))
        return XcodeCrash(
            event: event,
            filePath: path,
            fileMtime: attributes.modificationDate,
            fileSize: attributes.size
        )
    }

    private static func warning(for error: Error, path: String) -> CommandWarning {
        guard let parseError = error as? CrashReportParseError else {
            return CommandWarning(
                code: .xcodeParseFailed,
                message: "failed to parse \(path): \(error.localizedDescription)",
                path: path)
        }
        let reason = parseError.errorDescription ?? "unknown error"
        if case .unsupportedReport = parseError {
            return CommandWarning(code: .xcodeUnsupportedReport, message: "skipped \(path): \(reason)", path: path)
        }
        return CommandWarning(code: .xcodeParseFailed, message: "failed to parse \(path): \(reason)", path: path)
    }

    // Organizer keeps a raw-address twin next to a symbolicated report of one incident;
    // keep the most useful copy or `show`/`open` may pick the one without source locations.
    private static func dedupedByIncident(_ crashes: [XcodeCrash]) -> [XcodeCrash] {
        var bestByIncident: [String: XcodeCrash] = [:]
        for crash in crashes {
            if let current = bestByIncident[crash.event.id], !isMoreUseful(crash, than: current) {
                continue
            }
            bestByIncident[crash.event.id] = crash
        }
        return Array(bestByIncident.values)
    }

    private static func isMoreUseful(_ candidate: XcodeCrash, than incumbent: XcodeCrash) -> Bool {
        let candidateLocated = locatedFrameCount(of: candidate)
        let incumbentLocated = locatedFrameCount(of: incumbent)
        if candidateLocated != incumbentLocated { return candidateLocated > incumbentLocated }

        let candidateSymbolicated = symbolicatedFrameCount(of: candidate)
        let incumbentSymbolicated = symbolicatedFrameCount(of: incumbent)
        if candidateSymbolicated != incumbentSymbolicated { return candidateSymbolicated > incumbentSymbolicated }

        if candidate.fileMtime != incumbent.fileMtime { return candidate.fileMtime > incumbent.fileMtime }
        return candidate.filePath < incumbent.filePath
    }

    private static func locatedFrameCount(of crash: XcodeCrash) -> Int {
        crash.event.frames.filter { $0.file != nil }.count
    }

    private static func symbolicatedFrameCount(of crash: XcodeCrash) -> Int {
        crash.event.frames.filter { $0.isSymbolicated }.count
    }
}
