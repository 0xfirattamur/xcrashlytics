import ArgumentParser
import Foundation

struct BlameCommand: ContainerCommand {
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

    @Option(name: .long, help: "Report window and event cutoff: 7d (default), 24h, 30m, 2w, or all (90d). At most 90d.")
    var since: String = "7d"

    @Option(name: .long, help: "Number of Firebase issues to scan.")
    var issueLimit: Int = 30

    @Option(
        name: .long,
        help: "Number of sample events to inspect per issue. Counts in the output are of sampled events.")
    var eventsPerIssue: Int = 1

    @Option(name: .long, help: "Maximum number of Firebase event requests to run in parallel.")
    var concurrency: Int = 6

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        try validateInputs()
        let result = try await container.blameService.blame(makeRequest())
        return try container.resultEmitter.emit(result, using: BlamePresenter(), format: format)
    }

    private func validateInputs() throws {
        try OptionValidator.requirePositive(top, flag: "--top")
        try OptionValidator.requirePositive(issueLimit, flag: "--issue-limit")
        try OptionValidator.requirePositive(eventsPerIssue, flag: "--events-per-issue")
        try OptionValidator.requirePositive(concurrency, flag: "--concurrency")
    }

    private func makeRequest() -> BlameRequest {
        BlameRequest(
            top: top,
            since: since,
            issueLimit: issueLimit,
            eventsPerIssue: eventsPerIssue,
            concurrency: concurrency)
    }
}
