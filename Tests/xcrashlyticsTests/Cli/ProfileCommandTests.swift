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
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(
            appId: "1:1111111111:ios:debug",
            profiles: [
                "staging": AppProfile(appId: "1:2222222222:ios:staging", sourcePath: "Staging/GoogleService-Info.plist")
            ]
        ))
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())

        let cmd = try UseCommand.parse(["staging"])
        let output = try await cmd.execute(ctx.container)

        let saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.activeProfile == "staging")
        #expect(saved.resolvedAppId == "1:2222222222:ios:staging")
        #expect(output.contains("Using profile staging"))
    }

    @Test("errors when the profile is not configured")
    func errorsOnUnknownProfile() async throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: "1:1111111111:ios:debug"))
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())

        let cmd = try UseCommand.parse(["staging"])
        await #expect(throws: InvalidInputError.self) {
            _ = try await cmd.execute(ctx.container)
        }

        let saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.activeProfile == nil)
    }

    @Test("an invalid config file is reported, not mistaken for a missing profile")
    func invalidConfigPropagates() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: "{ this is hand edited, with a typo ")
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())

        let cmd = try UseCommand.parse(["debug"])
        await #expect(throws: ConfigError.invalidFile) { _ = try await cmd.execute(ctx.container) }

        #expect(String(data: try fileStore.readData(at: configPath), encoding: .utf8) == "{ this is hand edited, with a typo ")
    }

    @Test("profile names are trimmed and matched case-insensitively, including hand-edited keys")
    func trimsAndMatchesHandEditedKeys() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: #"{"profiles":{"Release":{"appId":"1:2:ios:r"}}}"#)
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())

        let output = try await UseCommand.parse(["  Release "]).execute(ctx.container)

        #expect(output == "Using profile release (1:2:ios:r).\n")
        #expect(try FileConfigRepository(fileStore: fileStore).load().activeProfile == "release")
    }

    @Test("a blank profile name is BAD_INPUT")
    func blankProfileName() async throws {
        let ctx = Platform.testing(fileStore: InMemoryFileStore(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())
        await #expect(throws: InvalidInputError.self) { _ = try await UseCommand.parse(["  "]).execute(ctx.container) }
    }

    @Test("a config that cannot be written fails use instead of printing success")
    func writeFailurePropagates() async throws {
        struct ReadOnly: FileStore {
            let base: InMemoryFileStore
            func exists(at path: String) -> Bool { base.exists(at: path) }
            func readData(at path: String) throws -> Data { try base.readData(at: path) }
            func writeDataAtomically(_ data: Data, to path: String) throws { throw FileStoreError(path: path, underlying: CocoaError(.fileWriteNoPermission)) }
            func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] { [] }
            func attributes(at path: String) throws -> FileAttributes { try base.attributes(at: path) }
        }
        let base = InMemoryFileStore()
        try FileConfigRepository(fileStore: base).save(Config(profiles: ["debug": AppProfile(appId: "1:1:ios:a")]))
        let console = SpyConsole()
        let ctx = Platform.testing(
            fileStore: ReadOnly(base: base),
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: SystemDateProvider(),
            console: console
        )

        await #expect(throws: FileStoreError.self) { _ = try await UseCommand.parse(["debug"]).execute(ctx.container) }
        #expect(console.outputs.isEmpty)
    }
}
