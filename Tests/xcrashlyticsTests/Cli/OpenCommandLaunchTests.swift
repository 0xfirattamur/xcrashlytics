import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics open — launching")
struct OpenCommandLaunchTests {
    private var cwd: String { FileManager.default.currentDirectoryPath }
    private let crashId = "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    private func xcodeContext(
        console: SpyConsole = SpyConsole(),
        withSource: Bool = true,
        brokenReport: Bool = false,
        handler: @escaping (String, [String]) -> SubprocessResult?
    ) throws -> Platform {
        let fileStore = InMemoryFileStore()
        let url = Bundle.module.url(forResource: "sample-symbolicated.crash", withExtension: nil, subdirectory: "Fixtures")!
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#)
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        fileStore.seed("\(crashDir)/A.crash", text: try String(contentsOf: url, encoding: .utf8))
        if brokenReport { fileStore.seed("\(crashDir)/broken.crash", text: "This is not a crash log.") }
        if withSource { fileStore.seed("\(cwd)/Sources/App/ExampleViewController.swift", text: "// source") }
        return Platform.testing(
            fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(handler: handler), dateProvider: SystemDateProvider(), console: console)
    }

    @Test("a failing xed is an error carrying its stderr, never 'Opened'")
    func failingXedIsAnError() async throws {
        let console = SpyConsole()
        let ctx = try xcodeContext(console: console) { _, _ in
            SubprocessResult(exitCode: 127, standardOutput: "", standardError: "env: xed: No such file or directory\n")
        }
        let cmd = try OpenCommand.parse([crashId])

        let error = await #expect(throws: EditorLaunchError.self) { _ = try await cmd.execute(ctx.container) }

        #expect(error?.exitCode == 127)
        let failure = CommandRunner.failure(for: try #require(error))
        #expect(failure.code == "INTERNAL")
        #expect(failure.message.contains("xed exited with status 127"))
        #expect(failure.message.contains("No such file or directory"))
        #expect(console.outputs.isEmpty)
    }

    @Test("XC load warnings are on stderr even when the editor launch fails")
    func warningsSurviveFailedLaunch() async throws {
        let console = SpyConsole()
        let ctx = try xcodeContext(console: console, brokenReport: true) { _, _ in
            SubprocessResult(exitCode: 127, standardOutput: "", standardError: "no xed")
        }
        let cmd = try OpenCommand.parse([crashId])

        await #expect(throws: EditorLaunchError.self) { _ = try await cmd.execute(ctx.container) }

        #expect(console.warnings.count == 1)
        #expect(console.warnings.first?.hasPrefix("XCODE_PARSE_FAILED: ") == true)
        #expect(console.outputs.isEmpty)
    }

    @Test("XC load warnings are on stderr before the editor is launched")
    func warningsPrecedeLaunch() async throws {
        let console = SpyConsole()
        var warningsAtLaunch: Int?
        let ctx = try xcodeContext(console: console, brokenReport: true) { _, _ in
            warningsAtLaunch = console.warnings.count
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        try await OpenCommand.parse([crashId]).execute(ctx.container)

        #expect(warningsAtLaunch == 1)
    }

    @Test("a failing /usr/bin/open on the raw-report fallback is an error too")
    func failingOpenIsAnError() async throws {
        let ctx = try xcodeContext(withSource: false) { executable, _ in
            executable == "/usr/bin/open" ? SubprocessResult(exitCode: 1, standardOutput: "", standardError: "The file does not exist.") : nil
        }
        let cmd = try OpenCommand.parse([crashId])

        let error = await #expect(throws: EditorLaunchError.self) { _ = try await cmd.execute(ctx.container) }

        #expect(error?.tool == "open")
        #expect(error?.stderr == "The file does not exist.")
    }

    @Test("an id without FB-/XC- is BAD_INPUT at run time, not a parse error")
    func badPrefixIsRuntimeBadInput() async throws {
        let cmd = try OpenCommand.parse(["abc"])
        let ctx = Platform.testing(fileStore: InMemoryFileStore(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: SystemDateProvider())

        let error = await #expect(throws: InvalidInputError.self) { _ = try await cmd.execute(ctx.container) }

        let failure = CommandRunner.failure(for: try #require(error))
        #expect(failure.code == "BAD_INPUT")
        #expect(failure.exitCode == 5)
        #expect(failure.message.contains("'abc'"))
    }
}
