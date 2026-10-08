import ArgumentParser
import Foundation

struct BreakdownCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "breakdown",
        abstract: """
            Exact events and users per app version, OS version, or device model \
            — for one issue or the whole app.
            """,
        discussion: """
        Numbers come from the Crashlytics reports over --since (default 7d, at most 90d), not from sampled
        events. With an issue id, rows are that issue's groups with events, most events first, with their share
        of the issue's events; `--by version` adds each version's total users and the percentage of them that
        hit the issue. Without an id the whole app is reported, with crash-free users where Crashlytics
        provides them. Takes the same ids as `show`.

        Examples:
          xcrashlytics breakdown FB-3aedb610eee1a41872d991ca62ce8566 --by version --since 30d
          xcrashlytics breakdown FB-3aedb610eee1a41872d991ca62ce8566 --by device --format json
          xcrashlytics breakdown --by version --format json
        """
    )

    @Argument(
        help: """
            Optional Firebase issue (FB-<id>, FB-<id>/events/<event>, or a console issue link). \
            Without it the report covers the whole app.
            """)
    var issue: String?

    @Option(name: .long, help: "What to split by: version, os, or device.")
    var by: BreakdownDimension

    @Option(name: .long, help: "Report window: 7d (default), 24h, 2w, 30d, or all (90d). At most 90d.")
    var since: String = ReportWindow.defaultSince

    @Option(name: .long, help: "Return only the first N rows (by events).")
    var limit: Int?

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        try OptionValidator.requirePositive(limit, flag: "--limit")
        let request = BreakdownRequest(issue: issue, dimension: by, since: since, limit: limit)
        let result = try await container.breakdownService.breakdown(request)
        return try container.resultEmitter.emit(result, using: BreakdownPresenter(), format: format)
    }
}
