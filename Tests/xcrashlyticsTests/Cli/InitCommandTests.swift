import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics init")
struct InitCommandTests {
    /// Path `init` writes to: always `<cwd>/.xcrashlytics.json` (no walk-up).
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    /// firebase-tools' stored-token path the login check reads (real home).
    private var firebaseToolsConfig: String {
        "\(HomeDirectoryLocator.path)/.config/configstore/firebase-tools.json"
    }

    /// A context where every setup check passes: firebase CLI on PATH, a stored
    /// refresh token, and a token endpoint that exchanges it successfully.
    private func loggedInContext(fileStore: InMemoryFileStore, console: Console = StandardStreamConsole()) -> Platform {
        fileStore.seed(firebaseToolsConfig, text: #"{"tokens":{"refresh_token":"R"}}"#)
        let httpClient = FakeHTTPClient { _ in
            FakeHTTPClient.response(
                FirebaseToolsTokenProvider.tokenEndpoint,
                status: 200,
                body: Data(#"{"access_token":"ya29.x","expires_in":3599}"#.utf8)
            )
        }
        let subprocessExecutor = StubSubprocessExecutor { _, args in
            args == ["which", "firebase"] ? SubprocessResult(exitCode: 0, standardOutput: "/usr/local/bin/firebase\n", standardError: "") : nil
        }
        return Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider(),
            httpClient: httpClient,
            console: console
        )
    }

    private func seedOrganizerCrash(_ fileStore: InMemoryFileStore) throws {
        let home = HomeDirectoryLocator.path
        let fixture = Bundle.module.url(forResource: "sample-symbolicated.crash", withExtension: nil, subdirectory: "Fixtures")!
        fileStore.seed(
            "\(home)/Library/Developer/Xcode/Products/com.example.app/Crashes/Points/a.xccrashpoint/Logs/one.crash",
            text: try String(contentsOf: fixture, encoding: .utf8))
    }

    @Test("fails the checks and writes nothing when firebase CLI is missing")
    func gatesWriteOnFailedChecks() async throws {
        let fileStore = InMemoryFileStore()
        // No process handler → `which firebase` throws → treated as "not installed".
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: SystemDateProvider(),
            httpClient: FakeHTTPClient()
        )

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
        ])
        await #expect(throws: ExitCode.self) {
            _ = try await cmd.execute(ctx.container)
        }

        #expect(fileStore.exists(at: configPath) == false)
    }

    @Test("writes and activates the named profile")
    func writesNamedProfile() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = loggedInContext(fileStore: fileStore)

        let cmd = try InitCommand.parse([
            "--profile", "staging",
            "--app-id", "1:1234567890:ios:staging",
        ])
        _ = try await cmd.execute(ctx.container)

        let saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.activeProfile == "staging")
        #expect(saved.profiles["staging"]?.appId == "1:1234567890:ios:staging")
        #expect(saved.resolvedAppId == "1:1234567890:ios:staging")
    }

    @Test("writes the bundle id into the profile when provided")
    func writesBundleId() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = loggedInContext(fileStore: fileStore, console: SpyConsole())

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
            "--bundle-id", "com.example.app",
        ])
        _ = try await cmd.execute(ctx.container)

        let saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.profiles["release"]?.bundleId == "com.example.app")
        #expect(saved.resolvedBundleId == "com.example.app")
    }

    @Test("rejects a malformed app id before writing anything")
    func rejectsMalformedAppId() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = loggedInContext(fileStore: fileStore)

        let cmd = try InitCommand.parse([
            "--app-id", "not-an-app-id",
            "--profile", "release",
        ])
        await #expect(throws: ExitCode.self) {
            _ = try await cmd.execute(ctx.container)
        }

        #expect(fileStore.exists(at: configPath) == false)
    }

    @Test("a token-exchange warning is advisory — config is still written")
    func tokenExchangeWarningStillWrites() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(firebaseToolsConfig, text: #"{"tokens":{"refresh_token":"R"}}"#)
        // CLI present and logged in, but the token endpoint fails transiently.
        let httpClient = FakeHTTPClient { _ in
            FakeHTTPClient.response(
                FirebaseToolsTokenProvider.tokenEndpoint,
                status: 500,
                body: Data(#"{"error":"server_error"}"#.utf8)
            )
        }
        let subprocessExecutor = StubSubprocessExecutor { _, args in
            args == ["which", "firebase"] ? SubprocessResult(exitCode: 0, standardOutput: "/usr/local/bin/firebase\n", standardError: "") : nil
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider(),
            httpClient: httpClient
        )

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
        ])
        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("[WARN] firebase token exchange failed"))
        #expect(output.contains("advisory"))
        #expect(fileStore.exists(at: configPath))
    }

    // MARK: - --scan

    private var cwd: String { FileManager.default.currentDirectoryPath }

    private func seedPlist(_ fileStore: InMemoryFileStore, _ relative: String, appId: String, bundleId: String?) {
        let bundle = bundleId.map { "<key>BUNDLE_ID</key><string>\($0)</string>" } ?? ""
        fileStore.seed("\(cwd)/\(relative)", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>\(appId)</string>\(bundle)</dict></plist>
        """)
    }

    @Test("--scan writes one profile per app and never guesses the active one")
    func scanWritesAllProfilesWithoutGuessing() async throws {
        let fileStore = InMemoryFileStore()
        seedPlist(fileStore, "Debug/GoogleService-Info.plist", appId: "1:1111111111:ios:debug", bundleId: "com.x.app.debug")
        seedPlist(fileStore, "Release/GoogleService-Info.plist", appId: "1:2222222222:ios:release", bundleId: "com.x.app")

        let output = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore).container)

        // `com.x.app.debug` extends `com.x.app`, so the bundle ids name the profiles, not the folders.
        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(config.profiles["debug"] == AppProfile(
            appId: "1:1111111111:ios:debug", bundleId: "com.x.app.debug", sourcePath: "Debug/GoogleService-Info.plist",
            extensionOf: "app"))
        #expect(config.profiles["app"]?.bundleId == "com.x.app")
        #expect(config.profiles["release"] == nil)
        #expect(config.activeProfile == nil)
        #expect(output.contains("xcrashlytics use <profile>"))
    }

    @Test("--scan keeps a still-valid active profile")
    func scanKeepsActiveProfile() async throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(activeProfile: "release", profiles: [
            "release": AppProfile(appId: "1:2222222222:ios:old"),
        ]))
        seedPlist(fileStore, "Debug/GoogleService-Info.plist", appId: "1:1111111111:ios:debug", bundleId: nil)
        seedPlist(fileStore, "Release/GoogleService-Info.plist", appId: "1:2222222222:ios:release", bundleId: "com.x.app")

        _ = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(config.activeProfile == "release")
        #expect(config.resolvedAppId == "1:2222222222:ios:release")
    }

    @Test("--scan activates a lone discovery and ignores build-output copies")
    func scanActivatesSingleAppIgnoringBuildCopies() async throws {
        let fileStore = InMemoryFileStore()
        seedPlist(fileStore, "App/GoogleService-Info.plist", appId: "1:1111111111:ios:app", bundleId: "com.x.app")
        seedPlist(fileStore, ".build/debug/App/GoogleService-Info.plist", appId: "1:1111111111:ios:app", bundleId: "com.x.app")
        seedPlist(fileStore, "Pods/Vendor/GoogleService-Info.plist", appId: "1:9999999999:ios:vendor", bundleId: "vendor")

        _ = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["app"])
        #expect(config.activeProfile == "app")
    }

    @Test("--scan with nothing to find fails and writes nothing")
    func scanFindsNothing() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = loggedInContext(fileStore: fileStore)
        let cmd = try InitCommand.parse(["--scan"])

        await #expect(throws: ExitCode.self) { _ = try await cmd.execute(ctx.container) }
        #expect(fileStore.exists(at: configPath) == false)
    }

    @Test("--scan and manual flags are mutually exclusive; manual needs both flags — as BAD_INPUT at run time")
    func flagValidation() async throws {
        let ctx = loggedInContext(fileStore: InMemoryFileStore())
        for arguments in [["--scan", "--app-id", "1:1:ios:x"], ["--app-id", "1:1:ios:x"], []] {
            let cmd = try InitCommand.parse(arguments)
            let error = await #expect(throws: InvalidInputError.self) { _ = try await cmd.execute(ctx.container) }
            let failure = CommandRunner.failure(for: try #require(error))
            #expect(failure.code == "BAD_INPUT" && failure.exitCode == 5, "\(arguments)")
        }
    }

    @Test("blank flag values are BAD_INPUT; padded ones are trimmed before they are stored")
    func trimsFlagValues() async throws {
        let blank = try InitCommand.parse(["--app-id", "  ", "--profile", "x"])
        await #expect(throws: InvalidInputError.self) { _ = try await blank.execute(loggedInContext(fileStore: InMemoryFileStore()).container) }

        let fileStore = InMemoryFileStore()
        let cmd = try InitCommand.parse([
            "--app-id", " 1:1234567890:ios:abcdef ", "--profile", " Rel ease ", "--bundle-id", " com.example.app ",
        ])
        _ = try await cmd.execute(loggedInContext(fileStore: fileStore).container)

        let saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.profiles["rel ease"] == AppProfile(appId: "1:1234567890:ios:abcdef", bundleId: "com.example.app"))
        #expect(saved.activeProfile == "rel ease")
    }

    @Test("an invalid existing config stops init and is left untouched")
    func invalidConfigIsNeverOverwritten() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: "{ hand edited, with a typo ")
        let cmd = try InitCommand.parse(["--app-id", "1:1234567890:ios:abcdef", "--profile", "x"])

        await #expect(throws: ConfigError.invalidFile) { _ = try await cmd.execute(loggedInContext(fileStore: fileStore).container) }

        #expect(String(data: try fileStore.readData(at: configPath), encoding: .utf8) == "{ hand edited, with a typo ")
    }

    @Test("re-running init for a profile keeps its bundle id unless a new one is given")
    func reInitKeepsBundleId() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = loggedInContext(fileStore: fileStore, console: SpyConsole())
        _ = try await InitCommand.parse(["--app-id", "1:1234567890:ios:abcdef", "--profile", "r", "--bundle-id", "com.x"])
            .execute(ctx.container)

        _ = try await InitCommand.parse(["--app-id", "1:1234567890:ios:newer", "--profile", "r"]).execute(ctx.container)
        var saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.profiles["r"]?.appId == "1:1234567890:ios:newer")
        #expect(saved.profiles["r"]?.bundleId == "com.x")

        _ = try await InitCommand.parse(["--app-id", "1:1234567890:ios:newer", "--profile", "r", "--bundle-id", "com.y"])
            .execute(ctx.container)
        saved = try FileConfigRepository(fileStore: fileStore).load()
        #expect(saved.profiles["r"]?.bundleId == "com.y")
    }

    @Test("--scan keeps a manually added bundle id when the plist has none")
    func scanKeepsBundleId() async throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(profiles: ["app": AppProfile(appId: "1:1:ios:old", bundleId: "com.manual")]))
        seedPlist(fileStore, "App/GoogleService-Info.plist", appId: "1:1111111111:ios:app", bundleId: nil)

        _ = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore).container)

        let profile = try #require(try FileConfigRepository(fileStore: fileStore).load().profiles["app"])
        #expect(profile.appId == "1:1111111111:ios:app")
        #expect(profile.bundleId == "com.manual")
        #expect(profile.sourcePath == "App/GoogleService-Info.plist")
    }

    @Test("--scan skips a malformed plist with a [WARN] naming it and still writes the rest")
    func scanWarnsOnMalformedFiles() async throws {
        let fileStore = InMemoryFileStore()
        let console = SpyConsole()
        seedPlist(fileStore, "Good/GoogleService-Info.plist", appId: "1:1111111111:ios:good", bundleId: "com.x")
        fileStore.seed("\(cwd)/Broken/GoogleService-Info.plist", text: "garbage not a plist")

        let output = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore, console: console).container)

        #expect(output.contains("[WARN] Broken/GoogleService-Info.plist is unreadable"))
        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["good"])
    }

    @Test("--scan of a root-level plist writes the 'default' profile and activates it")
    func scanRootLevelPlist() async throws {
        let fileStore = InMemoryFileStore()
        seedPlist(fileStore, "GoogleService-Info.plist", appId: "1:1111111111:ios:root", bundleId: "com.x")

        let output = try await InitCommand.parse(["--scan"]).execute(loggedInContext(fileStore: fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(config.activeProfile == "default")
        #expect(config.profiles["default"]?.appId == "1:1111111111:ios:root")
        #expect(output.contains("Active profile: default."))
    }

    @Test("login check: transport failure warns, Google rejection blocks")
    func loginCheckClassification() {
        #expect(ProfileSetupService.loginCheck(forTokenError: CrashlyticsClientError.network("offline"))
            == .warn("could not reach Google to verify the firebase login (offline)."))
        #expect(ProfileSetupService.loginCheck(forTokenError: AccessTokenError.tokenExchangeFailed("503"))
            == .warn("firebase token exchange failed: 503"))
        #expect(ProfileSetupService.loginCheck(forTokenError: AccessTokenError.refreshTokenInvalid("invalid_grant")).blocks)
        #expect(ProfileSetupService.loginCheck(forTokenError: AccessTokenError.firebaseLoginRequired).blocks)
        #expect(!ProfileSetupService.loginCheck(forTokenError: URLError(.notConnectedToInternet)).blocks)
    }
}
