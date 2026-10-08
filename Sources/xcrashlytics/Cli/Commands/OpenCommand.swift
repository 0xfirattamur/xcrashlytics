import ArgumentParser
import Foundation

struct OpenCommand: ContainerCommand {
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

    @Option(
        name: .customLong("crash-directory"),
        help: "XC- ids: Xcode crash directory to scan instead of the profile's Organizer directories. Repeatable.")
    var crashDirectories: [String] = []

    var reportFormat: OutputFormat { .text }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        let request = OpenRequest(id: id, crashDirectories: crashDirectories)
        let plan = try await container.crashOpenService.plan(request)
        container.resultEmitter.report(plan.warnings, format: .text)
        let result = try container.crashOpenService.launch(plan)
        return try container.resultEmitter.emit(result, using: OpenPresenter(), format: .text)
    }
}
