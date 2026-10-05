//
//  OutputContractTests.swift
//  xcrashlyticsTests
//
//  Where warnings go and how records are versioned — the parts of the v1
//  output contract that span commands.
//

import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    private func contextWithBrokenCrash() throws -> (CommandContext, RecordingConsole, String) {
        let fs = try makeConfig()
        let crashDir = "/crashes"
        fs.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))
        fs.seed("\(crashDir)/broken.crash", text: "This is not a crash log.")
        let console = RecordingConsole()
        let ctx = CommandContext(
            fileSystem: fs, processRunner: MockProcessRunner(), clock: FixedClock(), console: console)
        return (ctx.withFirebaseHTTP(makeIssuesHTTP()), console, crashDir)
    }

    @Test("JSON embeds loader warnings in the envelope and keeps stderr clean")
    func jsonEmbedsLoaderWarnings() async throws {
        let (ctx, console, crashDir) = try contextWithBrokenCrash()
        let cmd = try IssuesCommand.parse(["--xcode", "--format", "json"])

        let output = try await cmd.runWithContext(ctx, crashDirectories: [crashDir])

        let env = try Envelope(output)
        #expect(env.warningCodes == ["XCODE_PARSE_FAILED"])
        #expect(env.warnings.first?["path"]?.string == "\(crashDir)/broken.crash")
        #expect(env.data["xcodeCrashes"]?.array?.count == 1)
        #expect(console.warnings.isEmpty)
    }

    @Test("text output reports loader warnings on stderr, not stdout")
    func textReportsLoaderWarningsOnStderr() async throws {
        let (ctx, console, crashDir) = try contextWithBrokenCrash()
        let cmd = try IssuesCommand.parse(["--xcode"])

        let output = try await cmd.runWithContext(ctx, crashDirectories: [crashDir])

        #expect(console.warnings.count == 1)
        #expect(console.warnings.first?.contains("broken.crash") == true)
        #expect(!output.contains("broken.crash"))
    }

    @Test("NDJSON keeps stdout record-only; warnings go to stderr")
    func ndjsonKeepsWarningsOffStdout() async throws {
        let (ctx, console, crashDir) = try contextWithBrokenCrash()
        let cmd = try IssuesCommand.parse(["--xcode", "--format", "ndjson"])

        let output = try await cmd.runWithContext(ctx, crashDirectories: [crashDir])

        let records = try JSON.lines(output)
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0["schemaVersion"]?.int == 1 && $0["code"] == nil })
        #expect(console.warnings.count == 1)
    }
}
