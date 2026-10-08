import Foundation

struct CrashOpenService: Sendable {
    let clients: CrashlyticsClientProvider
    let sources: CrashSourceLoader
    let editor: EditorLauncher
    let sourceFiles: SourceFileLister
    let dateProvider: DateProvider
    let workingDirectory: String

    /// Separate from `launch` so the caller reports warnings even when the launch fails.
    func plan(_ request: OpenRequest) async throws -> OpenPlan {
        switch try CrashReference.parse(request.id, expecting: .openable) {
        case let .firebaseIssue(issueId):
            return try await firebasePlan(issueId: issueId, event: nil, id: request.id)
        case let .firebaseEvent(reference):
            return try await firebasePlan(issueId: reference.issueId, event: reference, id: request.id)
        case .xcodeCrash:
            return try xcodePlan(request)
        case .consoleLink:
            preconditionFailure("CrashReference.Expectation.openable never yields a console link")
        }
    }

    func launch(_ plan: OpenPlan) throws -> OpenResult {
        switch plan.target {
        case let .source(path, line):
            try editor.openSource(at: path, line: line)
        case let .rawReport(path, _):
            try editor.openFile(at: path)
        }
        return OpenResult(target: plan.target)
    }

    private func firebasePlan(
        issueId: String, event: CrashlyticsEventReference?, id: String
    ) async throws -> OpenPlan {
        let location = try await firebaseSourceLocation(issueId: issueId, eventReference: event, id: id)
        return OpenPlan(target: try resolveSource(location), warnings: [])
    }

    /// Opens the first crashed-thread frame whose file is in the checkout, skipping system/SDK
    /// frames that carry a source location; otherwise the raw report.
    private func xcodePlan(_ request: OpenRequest) throws -> OpenPlan {
        let load = try sources.xcodeCrashes(directories: request.crashDirectories)
        guard let crash = load.crashes.first(where: { $0.event.id == request.id }) else {
            throw InvalidInputError("no crash found with id '\(request.id)'.")
        }
        let located = crash.event.frames.compactMap { frame in
            frame.file.map { FrameSourceLocation(file: $0, line: frame.line) }
        }
        guard !located.isEmpty else {
            return rawReportPlan(crash, reason: "no source location in report", warnings: load.warnings)
        }
        // The topmost frame is the fallback so its resolution error explains why the raw report opens.
        let target = firstResolvable(located) ?? located[0]
        do {
            return OpenPlan(target: try resolveSource(target), warnings: load.warnings)
        } catch let error as InvalidInputError {
            let reason = error.message.hasSuffix(".") ? String(error.message.dropLast()) : error.message
            return rawReportPlan(crash, reason: reason, warnings: load.warnings)
        }
    }

    private func firstResolvable(_ located: [FrameSourceLocation]) -> FrameSourceLocation? {
        let extensions = Set(located.map { ($0.file as NSString).pathExtension.lowercased() }).subtracting([""])
        var filesByExtension: [String: [String]] = [:]
        for fileExtension in extensions {
            let files = try? sourceFiles.files(under: workingDirectory, withExtension: fileExtension)
            filesByExtension[fileExtension] = files ?? []
        }
        return SourceFileMatcher.firstResolvable(located, filesByExtension: filesByExtension, cwd: workingDirectory)
    }

    private func firebaseSourceLocation(
        issueId: String, eventReference: CrashlyticsEventReference?, id: String
    ) async throws -> FrameSourceLocation {
        let window = ReportWindow.maximum(now: dateProvider.currentDate()).interval
        let events = try await clients.client().fetchEvents(
            issueId: issueId, limit: EventSamplingLimits.limit, interval: window)
        let event: CrashlyticsEvent? = if let eventReference {
            events.first(where: eventReference.matches)
        } else {
            events.first
        }
        guard let event else {
            throw InvalidInputError("no Firebase event found for '\(id)'.")
        }
        guard let location = firebaseLocation(in: event) else {
            throw InvalidInputError(
                "no frame with a source location for '\(id)' — nothing to open in Xcode.")
        }
        return location
    }

    /// Prefers app frames; falls back to all frames so an SDK/system location still beats nothing.
    private func firebaseLocation(in event: CrashlyticsEvent) -> FrameSourceLocation? {
        let selector = FrameSelector()
        return firstSourceLocation(in: selector.frames(from: event, filter: FrameFilter(appFramesOnly: true)))
            ?? firstSourceLocation(in: selector.frames(from: event))
    }

    private func firstSourceLocation(in frames: [StackFrame]) -> FrameSourceLocation? {
        frames.lazy.compactMap { frame in frame.file.map { FrameSourceLocation(file: $0, line: frame.line) } }.first
    }

    private func resolveSource(_ location: FrameSourceLocation) throws -> OpenResult.Target {
        let fileExtension = try SourceFileMatcher.requiredExtension(of: location.file)
        let listed = try sourceFiles.files(under: workingDirectory, withExtension: fileExtension)
        let path = try SourceFileMatcher.resolve(location.file, among: listed, cwd: workingDirectory)
        return .source(path: path, line: location.line)
    }

    private func rawReportPlan(_ crash: XcodeCrash, reason: String, warnings: [CommandWarning]) -> OpenPlan {
        OpenPlan(target: .rawReport(path: crash.filePath, reason: reason), warnings: warnings)
    }
}
