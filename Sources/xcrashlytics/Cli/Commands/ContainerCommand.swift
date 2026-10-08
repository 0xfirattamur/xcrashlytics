import ArgumentParser

/// A subcommand that does its work against an `AppContainer`.
///
/// `run()` is the same for all of them: build the production container, then execute inside the
/// failure-reporting runner. Tests and the golden harness call the same two members with a test container.
protocol ContainerCommand: AsyncParsableCommand {
    /// The format failures are reported in.
    var reportFormat: OutputFormat { get }

    /// Returns the text the command printed (or wrote), for tests.
    @discardableResult
    func execute(_ container: AppContainer) async throws -> String
}

extension ContainerCommand {
    func run() async throws {
        let container = AppContainer.production()
        try await container.commandRunner.run(format: reportFormat) { try await execute(container) }
    }
}
