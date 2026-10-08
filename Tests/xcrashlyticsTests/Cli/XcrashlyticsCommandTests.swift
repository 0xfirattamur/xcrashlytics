import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics root command")
struct XcrashlyticsCommandTests {
    @Test("the advertised version is a semver release number")
    func versionIsSemver() throws {
        let version = try #require(XcrashlyticsCommand.configuration.version.nilIfEmpty)
        let pattern = #/^[0-9]+\.[0-9]+\.[0-9]+$/#
        #expect(version.wholeMatch(of: pattern) != nil, "version '\(version)' must be MAJOR.MINOR.PATCH — release.yml compares it to the tag")
    }

    // MARK: - Parse errors with structured output

    private func parse(_ arguments: [String], console: SpyConsole) throws -> ParsableCommand {
        try XcrashlyticsCommand.parseReportingFailures(arguments, console: console)
    }

    @Test("an invalid option value also goes through the contract")
    func validationFailureJSON() throws {
        let console = SpyConsole()
        #expect(throws: ExitCode(5)) { try parse(["issues", "--format", "ndjson", "--limit", "abc"], console: console) }
        #expect(try JSON.parse(try #require(console.outputs.first))["error"]?["code"]?.string == "BAD_INPUT")
    }

    @Test("--help and --version are never rewritten into a JSON error, even with --format json")
    func helpAndVersionUnchanged() {
        for arguments in [["--version", "--format", "json"], ["issues", "--help", "--format", "json"]] {
            let console = SpyConsole()
            // ArgumentParser reports help either as a thrown clean exit or as a
            // parsed HelpCommand whose run() exits cleanly; both are fine.
            do {
                _ = try parse(arguments, console: console)
            } catch {
                #expect(XcrashlyticsCommand.exitCode(for: error) == .success, "\(arguments)")
            }
            #expect(console.outputs.isEmpty, "\(arguments)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
