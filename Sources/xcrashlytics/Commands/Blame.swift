import ArgumentParser
import Foundation

struct BlameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blame",
        abstract: "Aggregate top blamed Firebase frames.",
        discussion: """
        Defaults are tuned for quick agent loops: 30 issues, 1 event per issue, and 6 concurrent event requests.
        Use --issue-limit and --events-per-issue for deeper investigations.
        """
    )

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Return the top N blamed frames.")
    var top: Int = 20

    @Option(name: .long, help: "Only include events since a relative duration like 7d, 24h, 30m, or all.")
    var since: String = "7d"

    @Option(name: .long, help: "Number of Firebase issues to scan.")
    var issueLimit: Int = 30

    @Option(name: .long, help: "Number of sample events to inspect per issue.")
    var eventsPerIssue: Int = 1

    @Option(name: .long, help: "Maximum number of Firebase event requests to run in parallel.")
    var concurrency: Int = 6

    func run() async throws {
        try await reportingFailures(jsonOutput: format.isJSON) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(
        _ ctx: CommandContext
    ) async throws -> String {
        let firebase = try ctx.crashlyticsClient()
        let cutoff = try SinceDuration.cutoffDate(from: since, now: ctx.clock.now())
        let issues = try await firebase.listIssues(maxIssues: max(1, issueLimit))
        let rows = try await FirebaseBlameAggregator(
            firebase: firebase,
            top: top,
            cutoff: cutoff,
            eventsPerIssue: max(1, eventsPerIssue),
            concurrency: max(1, concurrency)
        ).aggregate(issues: issues)

        let output: String
        switch format {
        case .text:
            output = BlameRenderer.text(rows)
        case .json:
            let payload = BlamePayload(
                since: since,
                issueLimit: issueLimit,
                eventsPerIssue: eventsPerIssue,
                concurrency: concurrency,
                items: rows
            )
            output = try BlameRenderer.json(payload)
        case .ndjson:
            output = try BlameRenderer.ndjson(rows)
        }
        ctx.console.output(output)
        return output
    }
}
