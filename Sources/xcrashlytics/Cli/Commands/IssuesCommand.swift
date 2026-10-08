import ArgumentParser
import Foundation

struct IssuesCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "issues",
        abstract: "List Firebase Crashlytics issues.",
        discussion: """
            Results follow Firebase topIssues impact order, counted over --since (default 7d, at most 90d).
            Bare issues fetches --limit issues. Queries and filters fetch a wider search window by default,
            then show the first --limit matches. --crash-directory implies --xcode; without a configured
            Firebase app, --xcode lists local crashes only.
            """
    )

    @Argument(help: "Optional title/subtitle/module/file/symbol query.")
    var query: String?

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Limit displayed issues (and, separately, displayed Xcode crashes).")
    var limit: Int = 20

    @Option(name: .long, help: "Number of Firebase issues to fetch before filtering (at most 2000).")
    var searchLimit: Int?

    @Flag(name: .long, help: "Search up to 2000 Firebase issues before filtering.")
    var all: Bool = false

    @Option(
        name: .long,
        help: "Case-insensitive substring filter for title/subtitle/module/file/symbol.")
    var match: String?

    @Option(
        name: .long,
        help: "Filter by Firebase error type, for example FATAL, NON_FATAL, EXC_BAD_ACCESS.")
    var type: String?

    @Option(name: .long, help: "Only include issues with at least N events.")
    var minEvents: Int?

    @Option(
        name: .long,
        help: """
            Only count events of this exact app version (6.16.0, or 6.16.0 (937) for one build); \
            issues and counts cover only it.
            """)
    var appVersion: String?

    @Option(
        name: .long,
        help: "Only count events of app versions greater than or equal to this one; issues and counts cover only them.")
    var sinceVersion: String?

    @Option(
        name: .long, help: "Only include issues whose parsed top file exactly matches this value.")
    var file: String?

    @Option(
        name: .long, help: "Only include issues whose parsed top symbol exactly matches this value."
    )
    var symbol: String?

    @Option(
        name: .long,
        help:
            "Report window for event and user counts: 24h, 7d, 30m, 2w, or all (90d). Default 7d, at most 90d."
    )
    var since: String?

    @Flag(name: .long, help: "Include exact per-day event counts for displayed issues (UTC days, from the report).")
    var byDay: Bool = false

    @Option(
        name: .long,
        help: "Events to scan per issue for --user-id (default 50).")
    var eventsPerIssue: Int?

    @Option(
        name: .long,
        help: "Only include issues with a sampled event for this exact Firebase user id.")
    var userId: String?

    @Option(
        name: .long,
        help: "Only include issues whose latest event metadata contains this NSError/domain string."
    )
    var domain: String?

    @Option(
        name: .long,
        help: "Filter latest event userInfo by key or key=value. Repeatable: --user-info-key a --user-info-key b.")
    var userInfoKey: [String] = []

    @Flag(name: .long, help: "Include local crash reports downloaded by the Xcode Organizer.")
    var xcode: Bool = false

    @Option(
        name: .customLong("crash-directory"),
        help: "Xcode crash directory to scan; implies --xcode. Repeatable.")
    var crashDirectories: [String] = []

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        try validateInputs()
        let result = try await container.issueSearchService.search(makeRequest())
        return try container.resultEmitter.emit(result, using: IssuesPresenter(), format: format)
    }

    private func makeRequest() -> IssuesRequest {
        let criteria = IssueCriteria(
            query: query,
            match: match,
            type: type,
            minEvents: minEvents,
            appVersion: appVersion,
            sinceVersion: sinceVersion,
            file: file,
            symbol: symbol,
            domain: domain,
            userInfoKey: userInfoKey,
            userId: userId)
        return IssuesRequest(
            criteria: criteria,
            limit: limit,
            searchLimit: searchLimit,
            all: all,
            since: since,
            byDay: byDay,
            eventsPerIssue: eventsPerIssue,
            xcode: xcode,
            crashDirectories: crashDirectories)
    }
}
