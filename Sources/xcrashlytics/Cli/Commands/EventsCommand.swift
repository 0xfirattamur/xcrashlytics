import ArgumentParser
import Foundation

struct EventsCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "List Firebase Crashlytics events for one or more issues.",
        discussion: """
        Memory and storage fields appear only when Firebase includes them for an event.
        Frame filter flags imply --frames-only for compact agent input.
        """
    )

    @Argument(help: "Canonical issue id, for example FB-ISSUE_ID. Comma-separated ids are accepted.")
    var issueId: String?

    @Option(name: .long, help: "Comma-separated issue ids, for example FB-a,FB-b.")
    var issues: String?

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Limit to N events per issue (default 10). Not combinable with --latest.")
    var limit: Int?

    @Option(name: .long, help: "Only include events for this exact Firebase user id.")
    var userId: String?

    @Option(
        name: .long,
        help: """
            Only include events since 7d, 24h, 30m, 2w, or all \
            (default: the newest events of the last 90d, the maximum).
            """)
    var since: String?

    @Flag(name: .long, help: "Fetch only the latest event.")
    var latest: Bool = false

    @Flag(name: .long, help: "Only emit frame data for each event.")
    var framesOnly: Bool = false

    @Flag(name: .long, help: "Only emit frames that look app-owned.")
    var appFramesOnly: Bool = false

    @Flag(name: .long, help: "Drop redacted, deduplicated, and known system/SDK frames.")
    var noSystemFrames: Bool = false

    @Flag(
        name: .long,
        help: "Only emit frames of Firebase's crashed thread; warns NO_CRASHED_THREAD when an event has none.")
    var crashingThreadOnly: Bool = false

    @Flag(
        name: .long,
        help: """
            Include each event's breadcrumbs (Analytics events before the crash); large, user ids redacted. \
            Ignored with frame-only output.
            """)
    var breadcrumbs: Bool = false

    @Option(
        name: .long,
        help: """
            A .dSYM bundle, or a directory searched recursively for them, \
            to symbolicate frames of its library (xcrun atos). Repeatable.
            """)
    var dsym: [String] = []

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        let request = try makeRequest()
        let result = try await container.eventQueryService.events(request)
        return try container.resultEmitter.emit(result, using: EventsPresenter(), format: format)
    }

    private func makeRequest() throws -> EventsRequest {
        let issueIds = try IssueIdList.parse([issueId, issues])
        try OptionValidator.requirePositive(limit, flag: "--limit")
        if latest, limit != nil {
            throw ValidationError("--latest and --limit cannot be combined; --latest returns one event.")
        }
        try OptionValidator.requireNonEmpty(userId, flag: "--user-id")
        let frameFilter = FrameFilter(
            appFramesOnly: appFramesOnly,
            noSystemFrames: noSystemFrames,
            crashingThreadOnly: crashingThreadOnly)
        return EventsRequest(
            issueIds: issueIds,
            limit: limit,
            latest: latest,
            userId: userId,
            since: since,
            frameFilter: frameFilter,
            framesOnly: framesOnly,
            includeBreadcrumbs: breadcrumbs,
            dsymPaths: dsym)
    }
}
