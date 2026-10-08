import Foundation
import Testing
@testable import xcrashlytics

@Suite("FoundationSubprocessExecutor")
struct FoundationSubprocessExecutorTests {
    private let runner = FoundationSubprocessExecutor()

    @Test("captures stdout, stderr and a non-zero exit code")
    func capturesStreamsAndExitCode() throws {
        let result = try runner.execute(
            executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"], standardInput: nil)
        #expect(result == SubprocessResult(exitCode: 3, standardOutput: "out\n", standardError: "err\n"))
    }

    @Test("feeds stdin to the child")
    func feedsStdin() throws {
        let result = try runner.execute(executable: "/bin/cat", arguments: [], standardInput: "hello")
        #expect(result.standardOutput == "hello")
        #expect(result.exitCode == 0)
    }

    @Test("output far beyond the 64 KB pipe buffer does not deadlock")
    func largeOutputOnBothStreams() throws {
        let script = "head -c 300000 /dev/zero | tr '\\0' 'o'; head -c 300000 /dev/zero | tr '\\0' 'e' >&2"
        let result = try runner.execute(executable: "/bin/sh", arguments: ["-c", script], standardInput: nil)
        #expect(result.standardOutput.count == 300_000)
        #expect(result.standardError.count == 300_000)
    }

    @Test("large stdin to a child that echoes it back does not deadlock")
    func largeStdinRoundTrip() throws {
        let input = String(repeating: "x", count: 300_000)
        let result = try runner.execute(executable: "/bin/cat", arguments: [], standardInput: input)
        #expect(result.standardOutput.count == 300_000)
    }

    @Test("a missing executable throws instead of returning a result")
    func missingExecutableThrows() {
        #expect(throws: (any Error).self) {
            try runner.execute(executable: "/nonexistent/xed", arguments: [], standardInput: nil)
        }
    }

    @Test("concurrent runs never inherit each other's pipes, so none of them hangs")
    func concurrentRunsFinish() async throws {
        let runner = runner
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try runner.execute(executable: "/bin/cat", arguments: [], standardInput: "run \(index)").standardOutput
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(outputs) == Set((0..<8).map { "run \($0)" }))
    }
}
