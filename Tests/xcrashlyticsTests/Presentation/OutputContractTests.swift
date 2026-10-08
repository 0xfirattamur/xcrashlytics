import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    private func contextWithBrokenCrash() throws -> (Platform, SpyConsole, String) {
        let fileStore = try makeConfig()
        let crashDir = "/crashes"
        fileStore.seed("\(crashDir)/A.crash", text: try XcodeFixtures.text("sample.crash"))
        fileStore.seed("\(crashDir)/broken.crash", text: "This is not a crash log.")
        let console = SpyConsole()
        let platform = Platform.testing(
            fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(), console: console)
        return (platform.withFirebaseHTTP(makeIssuesHTTP()), console, crashDir)
    }

    @Test("JSON embeds loader warnings in the envelope and keeps stderr clean")
    func jsonEmbedsLoaderWarnings() async throws {
        let (platform, console, crashDir) = try contextWithBrokenCrash()
        let command = try IssuesCommand.parse(["--xcode", "--crash-directory", crashDir, "--format", "json"])

        let output = try await command.execute(platform.container)

        let env = try Envelope(output)
        #expect(env.warningCodes == ["XCODE_PARSE_FAILED"])
        #expect(env.warnings.first?["path"]?.string == "\(crashDir)/broken.crash")
        #expect(env.data["xcodeCrashes"]?.array?.count == 1)
        #expect(console.warnings.isEmpty)
    }

    @Test("text output reports loader warnings on stderr, not stdout")
    func textReportsLoaderWarningsOnStderr() async throws {
        let (platform, console, crashDir) = try contextWithBrokenCrash()
        let command = try IssuesCommand.parse(["--xcode", "--crash-directory", crashDir])

        let output = try await command.execute(platform.container)

        #expect(console.warnings.count == 1)
        #expect(console.warnings.first?.contains("broken.crash") == true)
        #expect(console.warnings.first?.hasPrefix("XCODE_PARSE_FAILED: ") == true)
        #expect(!output.contains("broken.crash"))
    }

    @Test("NDJSON keeps stdout record-only; warnings go to stderr")
    func ndjsonKeepsWarningsOffStdout() async throws {
        let (platform, console, crashDir) = try contextWithBrokenCrash()
        let command = try IssuesCommand.parse(["--xcode", "--crash-directory", crashDir, "--format", "ndjson"])

        let output = try await command.execute(platform.container)

        let records = try JSON.lines(output)
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0["schemaVersion"]?.int == 1 && $0["code"] == nil })
        #expect(console.warnings.count == 1)
    }
}

@Suite("warning stderr rendering")
struct WarningRenderingTests {
    @Test("ndjson of no records is empty; each record carries schemaVersion")
    func ndjsonShape() throws {
        struct Row: Encodable { var id: String }
        #expect(try JSONPayloadEncoder().ndjson([Row]()) == "")
        let lines = try JSON.lines(try JSONPayloadEncoder().ndjson([Row(id: "a"), Row(id: "b")]))
        #expect(lines.map { $0["id"]?.string } == ["a", "b"])
        #expect(lines.allSatisfy { $0["schemaVersion"]?.int == 1 })
    }
}
