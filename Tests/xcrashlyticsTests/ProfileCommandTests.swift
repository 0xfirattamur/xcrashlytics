import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics use")
struct ProfileCommandTests {
    /// Path `use` resolves to: `<cwd>/.xcrashlytics.json`. Discovery scans `<cwd>`.
    private var cwd: String { FileManager.default.currentDirectoryPath }
    private var configPath: String { "\(cwd)/.xcrashlytics.json" }

    @Test("switches to an existing configured profile")
    func switchesConfiguredProfile() async throws {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(
            appId: "1:1111111111:ios:debug",
            profiles: [
                "staging": AppProfile(appId: "1:2222222222:ios:staging", sourcePath: "Staging/GoogleService-Info.plist")
            ]
        ))
        let ctx = CommandContext(fileSystem: fs, processRunner: MockProcessRunner(), clock: SystemClock())

        let cmd = try UseCommand.parse(["staging"])
        let output = try await cmd.runWithContext(ctx)

        let saved = try ConfigFile(fileSystem: fs).load()
        #expect(saved.activeProfile == "staging")
        #expect(saved.resolvedAppId == "1:2222222222:ios:staging")
        #expect(output.contains("Using profile staging"))
    }

    @Test("errors when the profile is not configured")
    func errorsOnUnknownProfile() async throws {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: "1:1111111111:ios:debug"))
        let ctx = CommandContext(fileSystem: fs, processRunner: MockProcessRunner(), clock: SystemClock())

        let cmd = try UseCommand.parse(["staging"])
        await #expect(throws: ValidationError.self) {
            _ = try await cmd.runWithContext(ctx)
        }

        let saved = try ConfigFile(fileSystem: fs).load()
        #expect(saved.activeProfile == nil)
    }
}
