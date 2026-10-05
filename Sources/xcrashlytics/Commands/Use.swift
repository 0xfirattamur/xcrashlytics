import ArgumentParser
import Foundation

struct UseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Switch the active Firebase app profile."
    )

    @Argument(help: "Profile name, for example debug, staging, prerelease, or release.")
    var profile: String

    func run() async throws {
        try await reportingFailures(jsonOutput: false) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(_ ctx: CommandContext) async throws -> String {
        let configFile = ConfigFile(fileSystem: ctx.fileSystem)
        var config = (try? configFile.load()) ?? Config()
        let name = profile.lowercased()

        guard let existing = config.profiles[name] else {
            throw ValidationError("profile '\(profile)' not found. Add it with `xcrashlytics init --profile \(profile) --app-id <GOOGLE_APP_ID>`.")
        }
        config.activeProfile = name
        try configFile.save(config)

        let output = "Using profile \(name) (\(existing.appId)).\n"
        ctx.console.output(output)

        return output
    }
}
