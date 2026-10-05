import ArgumentParser
import Foundation

struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a crash's source location in Xcode via xed.",
        discussion: """
        Examples:
          xcrashlytics open FB-3aedb610eee1a41872d991ca62ce8566
          xcrashlytics open FB-3aedb610eee1a41872d991ca62ce8566/events/E1
          xcrashlytics open XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE

        Crash frames carry file names only, so the file is resolved inside the current directory — run from the app's repo root.
        """
    )

    @Argument(help: "Crash id (XC-<uuid> or FB-<id>).")
    var id: String

    func validate() throws {
        guard id.hasPrefix("FB-") || id.hasPrefix("XC-") else {
            throw ValidationError("id must start with FB- or XC-; got '\(id)'.")
        }
    }

    func run() async throws {
        try await reportingFailures(jsonOutput: false) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(_ ctx: CommandContext) async throws -> String {
        // validate() guarantees the prefix is FB- or XC- before this runs.
        try await id.hasPrefix("FB-")
            ? openFirebaseCrash(ctx: ctx)
            : openXcodeCrash(ctx: ctx)
    }

    /// FB- ids: the crash lives in Firebase — find its source location and jump there.
    private func openFirebaseCrash(ctx: CommandContext) async throws -> String {
        let location = try await firebaseSourceLocation(ctx: ctx)
        return try openInXcode(location, ctx: ctx)
    }

    /// XC- ids: the crash is a local Organizer report. Open the first
    /// crashed-thread frame whose file is actually in the checkout — skipping
    /// the system/SDK frames that merely carry a source location and sit on top
    /// of the stack. Otherwise open the raw report, saying why.
    private func openXcodeCrash(ctx: CommandContext) throws -> String {
        let crash = try xcodeCrash(ctx: ctx)
        let cwd = FileManager.default.currentDirectoryPath
        let located = crash.event.frames.compactMap { frame in
            frame.file.map { (file: $0, line: frame.line) }
        }
        guard !located.isEmpty else {
            return try openRawReport(crash, reason: "no source location in report", ctx: ctx)
        }
        // Prefer the first frame that resolves in the checkout; fall back to the
        // topmost located frame so its resolution error explains the fallback.
        let target = firstResolvable(located, fs: ctx.fileSystem, cwd: cwd) ?? located[0]
        do {
            return try openInXcode((target.file, target.line), ctx: ctx)
        } catch let error as ValidationError {
            let reason = error.message.hasSuffix(".") ? String(error.message.dropLast()) : error.message
            return try openRawReport(crash, reason: reason, ctx: ctx)
        }
    }

    /// First located frame whose file resolves to exactly one source file under
    /// `cwd` (build dirs excluded). Enumerates each distinct extension once and
    /// counts non-build matches per basename, so walking many frames stays cheap.
    private func firstResolvable(
        _ located: [(file: String, line: Int?)],
        fs: FileSystem,
        cwd: String
    ) -> (file: String, line: Int?)? {
        let extensions = Set(located.map { ($0.file as NSString).pathExtension.lowercased() })
            .subtracting([""])
        var matchesByName: [String: Int] = [:]
        for ext in extensions {
            for path in (try? fs.enumerate(at: cwd, matchingExtensions: [ext])) ?? [] where !Self.isInBuildDirectory(path, cwd: cwd) {
                matchesByName[(path as NSString).lastPathComponent, default: 0] += 1
            }
        }
        return located.first { matchesByName[$0.file] == 1 }
    }

    // MARK: - Locating the crash

    /// First frame with a source location in the id's Firebase event — the
    /// `FB-…/events/…` event when the id names one, else the issue's newest.
    private func firebaseSourceLocation(ctx: CommandContext) async throws -> (file: String, line: Int?) {
        let firebase = try ctx.crashlyticsClient()
        let eventReference = FirebaseEventRef(id)
        let issueId = eventReference?.issueId ?? FirebaseIdentifiers.issueId(from: id)
        let events = try await firebase.listEvents(issueID: issueId, maxEvents: FirebaseEventSampling.limit)
        let event: FirebaseEvent? = if let eventReference {
            events.first { FirebaseIdentifiers.canonicalEventId($0, issueId: eventReference.issueId) == id }
        } else {
            events.first
        }
        guard let event else {
            throw ValidationError("no Firebase event found for '\(id)'.")
        }
        guard let location = firebaseLocation(in: event) else {
            throw ValidationError("no frame with a source location for '\(id)' — nothing to open in Xcode.")
        }
        return location
    }

    private func xcodeCrash(ctx: CommandContext) throws -> XcodeCrash {
        let load = ctx.loadXcodeCrashes(directories: try ctx.xcodeCrashDirectories())
        ctx.report(load.warnings, format: .text)
        guard let match = load.crashes.first(where: { $0.event.id == id }) else {
            throw ValidationError("no crash found with id '\(id)'.")
        }
        return match
    }

    private func firstSourceLocation(in frames: [Frame]) -> (file: String, line: Int?)? {
        for frame in frames {
            if let file = frame.file { return (file, frame.line) }
        }
        return nil
    }

    /// First located frame after the app-frames filter (drops Crashlytics SDK
    /// noise and system libraries); falls back to the unfiltered list so an
    /// SDK/system location still beats opening nothing.
    private func firebaseLocation(in event: FirebaseEvent) -> (file: String, line: Int?)? {
        firstSourceLocation(
            in: FirebaseEventFrames.frames(from: event, options: FirebaseFrameFilterOptions(appFramesOnly: true))
        ) ?? firstSourceLocation(in: FirebaseEventFrames.frames(from: event))
    }

    // MARK: - Opening

    private func openInXcode(_ location: (file: String, line: Int?), ctx: CommandContext) throws -> String {
        let path = try sourcePath(for: location.file, fs: ctx.fileSystem)
        // xed has no path:line syntax — the line goes through --line.
        let arguments = location.line.map { ["xed", "--line", "\($0)", path] } ?? ["xed", path]
        _ = try ctx.processRunner.run(executable: "/usr/bin/env", arguments: arguments, stdin: nil)
        let target = location.line.map { "\(path):\($0)" } ?? path
        let msg = "Opened \(target) in Xcode.\n"
        ctx.console.output(msg)
        return msg
    }

    /// Crash frames name files without paths ("BlurDetectionService.swift"),
    /// but `xed` needs a real path — find exactly one file with that name
    /// under the current directory, or refuse rather than guess.
    private func sourcePath(for file: String, fs: FileSystem) throws -> String {
        let ext = (file as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else {
            throw ValidationError("frame file '\(file)' has no extension — cannot resolve it to a source file.")
        }
        let cwd = FileManager.default.currentDirectoryPath
        let allMatches = try fs.enumerate(at: cwd, matchingExtensions: [ext])
            .filter { $0.hasSuffix("/\(file)") }
        let matches = allMatches.filter { !Self.isInBuildDirectory($0, cwd: cwd) }
        switch matches.count {
        case 1:
            return matches[0]
        case 0 where !allMatches.isEmpty:
            throw ValidationError("'\(file)' only matches inside build directories under \(cwd) — run from the app's repo root.")
        case 0:
            throw ValidationError("found no file named '\(file)' under \(cwd) — run from the app's repo root.")
        default:
            throw ValidationError("'\(file)' is ambiguous under \(cwd):\n" + matches.map { "  \($0)" }.joined(separator: "\n"))
        }
    }

    /// Build products duplicate source that lives elsewhere (SPM checkouts in
    /// .build/DerivedData) — never the copy the user wants to edit. Only
    /// components below cwd count, so a cwd like ~/build/app is unaffected.
    private static let buildDirectoryComponents: Set<Substring> = [".build", "build", "DerivedData"]

    private static func isInBuildDirectory(_ path: String, cwd: String) -> Bool {
        let relative = path.hasPrefix(cwd) ? path.dropFirst(cwd.count) : path[...]
        return relative.split(separator: "/").contains { Self.buildDirectoryComponents.contains($0) }
    }

    private func openRawReport(_ crash: XcodeCrash, reason: String, ctx: CommandContext) throws -> String {
        _ = try ctx.processRunner.run(executable: "/usr/bin/open", arguments: [crash.filePath], stdin: nil)
        let msg = "Opened raw report at \(crash.filePath) (\(reason)).\n"
        ctx.console.output(msg)
        return msg
    }
}
