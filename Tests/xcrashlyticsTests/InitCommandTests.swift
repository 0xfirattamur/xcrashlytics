import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics init")
struct InitCommandTests {
    /// Path `init` writes to: the nearest config walking up from cwd, or
    /// `<cwd>/.xcrashlytics.json` when none exists yet.
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    /// firebase-tools' stored-token path the login check reads (real home).
    private var firebaseToolsConfig: String {
        "\(NSString(string: "~").expandingTildeInPath)/.config/configstore/firebase-tools.json"
    }

    /// A context where every setup check passes: firebase CLI on PATH, a stored
    /// refresh token, and a token endpoint that exchanges it successfully.
    private func loggedInContext(fs: InMemoryFileSystem, console: CLIConsole = StandardConsole()) -> CommandContext {
        fs.seed(firebaseToolsConfig, text: #"{"tokens":{"refresh_token":"R"}}"#)
        let http = MockHTTPTransport { _ in
            MockHTTPTransport.response(
                FirebaseToolsTokenProvider.tokenEndpoint,
                status: 200,
                body: Data(#"{"access_token":"ya29.x","expires_in":3599}"#.utf8)
            )
        }
        let proc = MockProcessRunner { _, args in
            args == ["which", "firebase"] ? ProcessResult(exitCode: 0, stdout: "/usr/local/bin/firebase\n", stderr: "") : nil
        }
        return CommandContext(
            fileSystem: fs,
            processRunner: proc,
            clock: SystemClock(),
            httpTransport: http,
            console: console
        )
    }

    private func seedOrganizerCrash(_ fs: InMemoryFileSystem) throws {
        let home = NSString(string: "~").expandingTildeInPath
        let fixture = Bundle.module.url(forResource: "sample-symbolicated.crash", withExtension: nil, subdirectory: "Fixtures")!
        fs.seed(
            "\(home)/Library/Developer/Xcode/Products/com.example.app/Crashes/Points/a.xccrashpoint/Logs/one.crash",
            text: try String(contentsOf: fixture, encoding: .utf8))
    }

    @Test("fails the checks and writes nothing when firebase CLI is missing")
    func gatesWriteOnFailedChecks() async throws {
        let fs = InMemoryFileSystem()
        // No process handler → `which firebase` throws → treated as "not installed".
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: SystemClock(),
            httpTransport: MockHTTPTransport()
        )

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
        ])
        await #expect(throws: ExitCode.self) {
            _ = try await cmd.runWithContext(ctx)
        }

        #expect(fs.fileExists(at: configPath) == false)
    }

    @Test("writes config and reports it holds no secrets once checks pass")
    func writesConfigWhenReady() async throws {
        let fs = InMemoryFileSystem()
        let console = RecordingConsole()
        try seedOrganizerCrash(fs)
        let ctx = loggedInContext(fs: fs, console: console)

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
            "--bundle-id", "com.example.app",
        ])
        let output = try await cmd.runWithContext(ctx)

        #expect(output.contains("All checks passed."))
        #expect(output.contains("app ids only, no secrets"))
        #expect(output.contains("commit it so the team shares the setup"))
        #expect(console.outputs.joined() == output)
    }

    @Test("writes and activates the named profile")
    func writesNamedProfile() async throws {
        let fs = InMemoryFileSystem()
        let ctx = loggedInContext(fs: fs)

        let cmd = try InitCommand.parse([
            "--profile", "staging",
            "--app-id", "1:1234567890:ios:staging",
        ])
        _ = try await cmd.runWithContext(ctx)

        let saved = try ConfigFile(fileSystem: fs).load()
        #expect(saved.activeProfile == "staging")
        #expect(saved.profiles["staging"]?.appId == "1:1234567890:ios:staging")
        #expect(saved.resolvedAppId == "1:1234567890:ios:staging")
    }

    @Test("writes the bundle id into the profile when provided")
    func writesBundleId() async throws {
        let fs = InMemoryFileSystem()
        let ctx = loggedInContext(fs: fs, console: RecordingConsole())

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
            "--bundle-id", "com.example.app",
        ])
        _ = try await cmd.runWithContext(ctx)

        let saved = try ConfigFile(fileSystem: fs).load()
        #expect(saved.profiles["release"]?.bundleId == "com.example.app")
        #expect(saved.resolvedBundleId == "com.example.app")
    }

    @Test("rejects a malformed app id before writing anything")
    func rejectsMalformedAppId() async throws {
        let fs = InMemoryFileSystem()
        let ctx = loggedInContext(fs: fs)

        let cmd = try InitCommand.parse([
            "--app-id", "not-an-app-id",
            "--profile", "release",
        ])
        await #expect(throws: ExitCode.self) {
            _ = try await cmd.runWithContext(ctx)
        }

        #expect(fs.fileExists(at: configPath) == false)
    }

    @Test("warns when --bundle-id is omitted")
    func warnsWithoutBundleId() async throws {
        let fs = InMemoryFileSystem()
        let console = RecordingConsole()
        let ctx = loggedInContext(fs: fs, console: console)
        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
        ])
        _ = try await cmd.runWithContext(ctx)
        let out = console.outputs.joined()
        #expect(out.contains("[WARN] no bundle id — Xcode crash commands need one. Re-run with --bundle-id <BUNDLE_ID>."))
        #expect(fs.fileExists(at: configPath))
    }

    @Test("warns when the bundle id has no downloaded Organizer crashes yet")
    func warnsWhenNoOrganizerCrashes() async throws {
        let fs = InMemoryFileSystem()
        let console = RecordingConsole()
        let ctx = loggedInContext(fs: fs, console: console)
        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
            "--bundle-id", "com.example.app",
        ])
        _ = try await cmd.runWithContext(ctx)
        let out = console.outputs.joined()
        #expect(out.contains("[WARN] no Organizer crashes for com.example.app yet — open Xcode Organizer once to download."))
        #expect(fs.fileExists(at: configPath))
    }

    @Test("no bundle-id warning when Organizer crashes exist")
    func noWarnWhenCrashesExist() async throws {
        let fs = InMemoryFileSystem()
        let console = RecordingConsole()
        try seedOrganizerCrash(fs)
        let ctx = loggedInContext(fs: fs, console: console)
        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
            "--bundle-id", "com.example.app",
        ])
        _ = try await cmd.runWithContext(ctx)
        let out = console.outputs.joined()
        #expect(!out.contains("no Organizer crashes"))
        #expect(!out.contains("no bundle id"))
    }

    @Test("a token-exchange warning is advisory — config is still written")
    func tokenExchangeWarningStillWrites() async throws {
        let fs = InMemoryFileSystem()
        fs.seed(firebaseToolsConfig, text: #"{"tokens":{"refresh_token":"R"}}"#)
        // CLI present and logged in, but the token endpoint fails transiently.
        let http = MockHTTPTransport { _ in
            MockHTTPTransport.response(
                FirebaseToolsTokenProvider.tokenEndpoint,
                status: 500,
                body: Data(#"{"error":"server_error"}"#.utf8)
            )
        }
        let proc = MockProcessRunner { _, args in
            args == ["which", "firebase"] ? ProcessResult(exitCode: 0, stdout: "/usr/local/bin/firebase\n", stderr: "") : nil
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: proc,
            clock: SystemClock(),
            httpTransport: http
        )

        let cmd = try InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef",
            "--profile", "release",
        ])
        let output = try await cmd.runWithContext(ctx)

        #expect(output.contains("[WARN] firebase token exchange failed"))
        #expect(output.contains("advisory"))
        #expect(fs.fileExists(at: configPath))
    }

    // MARK: - --scan

    private var cwd: String { FileManager.default.currentDirectoryPath }

    private func seedPlist(_ fs: InMemoryFileSystem, _ relative: String, appId: String, bundleId: String?) {
        let bundle = bundleId.map { "<key>BUNDLE_ID</key><string>\($0)</string>" } ?? ""
        fs.seed("\(cwd)/\(relative)", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>\(appId)</string>\(bundle)</dict></plist>
        """)
    }

    @Test("--scan writes one profile per app and never guesses the active one")
    func scanWritesAllProfilesWithoutGuessing() async throws {
        let fs = InMemoryFileSystem()
        seedPlist(fs, "Debug/GoogleService-Info.plist", appId: "1:1111111111:ios:debug", bundleId: "com.x.app.debug")
        seedPlist(fs, "Release/GoogleService-Info.plist", appId: "1:2222222222:ios:release", bundleId: "com.x.app")

        let output = try await InitCommand.parse(["--scan"]).runWithContext(loggedInContext(fs: fs))

        let config = try ConfigFile(fileSystem: fs).load()
        #expect(config.profiles["debug"] == AppProfile(
            appId: "1:1111111111:ios:debug", bundleId: "com.x.app.debug", sourcePath: "Debug/GoogleService-Info.plist"))
        #expect(config.profiles["release"]?.bundleId == "com.x.app")
        #expect(config.activeProfile == nil)
        #expect(output.contains("xcrashlytics use <profile>"))
    }

    @Test("--scan keeps a still-valid active profile")
    func scanKeepsActiveProfile() async throws {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(activeProfile: "release", profiles: [
            "release": AppProfile(appId: "1:2222222222:ios:old"),
        ]))
        seedPlist(fs, "Debug/GoogleService-Info.plist", appId: "1:1111111111:ios:debug", bundleId: nil)
        seedPlist(fs, "Release/GoogleService-Info.plist", appId: "1:2222222222:ios:release", bundleId: "com.x.app")

        _ = try await InitCommand.parse(["--scan"]).runWithContext(loggedInContext(fs: fs))

        let config = try ConfigFile(fileSystem: fs).load()
        #expect(config.activeProfile == "release")
        #expect(config.resolvedAppId == "1:2222222222:ios:release")
    }

    @Test("--scan activates a lone discovery and ignores build-output copies")
    func scanActivatesSingleAppIgnoringBuildCopies() async throws {
        let fs = InMemoryFileSystem()
        seedPlist(fs, "App/GoogleService-Info.plist", appId: "1:1111111111:ios:app", bundleId: "com.x.app")
        seedPlist(fs, ".build/debug/App/GoogleService-Info.plist", appId: "1:1111111111:ios:app", bundleId: "com.x.app")
        seedPlist(fs, "Pods/Vendor/GoogleService-Info.plist", appId: "1:9999999999:ios:vendor", bundleId: "vendor")

        _ = try await InitCommand.parse(["--scan"]).runWithContext(loggedInContext(fs: fs))

        let config = try ConfigFile(fileSystem: fs).load()
        #expect(Set(config.profiles.keys) == ["app"])
        #expect(config.activeProfile == "app")
    }

    @Test("--scan with nothing to find fails and writes nothing")
    func scanFindsNothing() async throws {
        let fs = InMemoryFileSystem()
        let ctx = loggedInContext(fs: fs)
        let cmd = try InitCommand.parse(["--scan"])

        await #expect(throws: ExitCode.self) { _ = try await cmd.runWithContext(ctx) }
        #expect(fs.fileExists(at: configPath) == false)
    }

    @Test("--scan and manual flags are mutually exclusive; manual needs both flags")
    func scanFlagValidation() {
        #expect(throws: (any Error).self) { try InitCommand.parse(["--scan", "--app-id", "1:1:ios:x"]) }
        #expect(throws: (any Error).self) { try InitCommand.parse(["--app-id", "1:1:ios:x"]) }
        #expect(throws: (any Error).self) { try InitCommand.parse([]) }
    }
}
