import ArgumentParser
import Foundation

struct GroupsCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "groups",
        abstract: "Show related Firebase issues and optional Xcode crashes."
    )

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Maximum number of Firebase issues to fetch.")
    var firebaseLimit: Int = 100

    @Argument(help: "Optional Firebase issue id, for example FB-ISSUE_ID.")
    var issue: String?

    @Option(name: .long, help: "Limit to N groups.")
    var limit: Int?

    @Flag(name: .long, help: "Include local crash reports downloaded by the Xcode Organizer.")
    var xcode: Bool = false

    @Option(name: .customLong("crash-directory"), help: "Xcode crash directory to scan. Repeatable.")
    var crashDirectories: [String] = []

    @Option(name: .long, help: "Firebase window for event and user totals, e.g. 7d (default), 30d, 90d, or all (90d).")
    var since: String?

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        try validateInputs()
        let request = GroupsRequest(
            issue: issue,
            firebaseLimit: firebaseLimit,
            limit: limit,
            since: since,
            includesXcode: xcode,
            crashDirectories: crashDirectories)
        let result = try await container.crashGroupingService.group(request)
        return try container.resultEmitter.emit(result, using: GroupsPresenter(), format: format)
    }

    /// Checked here, not in `validate()`, so a failure still prints the JSON error body when asked for.
    private func validateInputs() throws {
        guard format != .ndjson else {
            throw ValidationError("--format ndjson is not supported by this command.")
        }
        if let limit, limit < 1 {
            throw ValidationError("--limit must be at least 1; got \(limit).")
        }
        try OptionValidator.requirePositive(firebaseLimit, flag: "--firebase-limit")
    }
}
