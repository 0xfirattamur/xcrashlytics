import ArgumentParser

struct UseCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Switch the active Firebase app profile."
    )

    @Argument(help: "Profile name, for example debug, staging, prerelease, or release.")
    var profile: String

    var reportFormat: OutputFormat { .text }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        let result = try container.profileSelectionService.use(UseRequest(profile: profile))
        return try container.resultEmitter.emit(result, using: UsePresenter(), format: .text)
    }
}
