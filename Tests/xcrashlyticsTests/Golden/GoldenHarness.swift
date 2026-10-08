import ArgumentParser
import Foundation
@testable import xcrashlytics

/// Everything a user can observe from one invocation.
struct GoldenResult: Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    /// Files the command created or changed in the in-memory store, by normalized path.
    var writtenFiles: [String: String]
    /// Every HTTP request the command sent, as `METHOD url`, sorted (concurrent requests have no stable order).
    var requests: [String]

    /// The golden file body: stdout, stderr, exit code, the requests sent, then written files.
    var serialized: String {
        var text = "=== stdout ===\n\(stdout)=== stderr ===\n\(stderr)=== exit ===\n\(exitCode)\n"
        text += "=== requests ===\n" + requests.map { $0 + "\n" }.joined()
        for path in writtenFiles.keys.sorted() {
            text += "=== file \(path) ===\n\(writtenFiles[path] ?? "")"
            if writtenFiles[path]?.hasSuffix("\n") == false { text += "\n" }
        }
        return text
    }
}

/// Console that keeps stdout and stderr as the user would see them, in write order per stream.
final class GoldenConsole: Console, @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""

    var stdout: String { lock.withLock { out } }
    var stderr: String { lock.withLock { err } }

    func writeOutput(_ text: String) { lock.withLock { out += text } }
    func reportWarning(_ message: String) { writeDiagnostic("warning: \(message)\n") }
    func writeDiagnostic(_ text: String) { lock.withLock { err += text } }
}

/// Runs the CLI the way a user would, against a deterministic in-memory world.
///
/// `run(_:world:)` is the only place that knows how a command line becomes a
/// command, a dependency container and a failure report. Refactors that change
/// that wiring update this adapter, nothing else.
enum GoldenHarness {
    /// Terminal width ArgumentParser wraps help and usage text to.
    static let helpColumns = 80

    static func run(_ arguments: [String], world: GoldenWorld = GoldenWorld()) async -> GoldenResult {
        let console = GoldenConsole()
        let built = world.build(console: console)
        var exitCode: Int32 = 0
        do {
            let command = try XcrashlyticsCommand.parseReportingFailures(arguments, console: console)
            try await execute(command, context: built.context, console: console)
        } catch {
            exitCode = finish(withError: error, console: console)
        }
        return GoldenResult(
            stdout: normalize(console.stdout),
            stderr: normalize(console.stderr),
            exitCode: exitCode,
            writtenFiles: built.writtenFiles().mapValues(normalize)
                .reduce(into: [:]) { $0[normalize($1.key)] = $1.value },
            requests: built.requests()
        )
    }

    /// Mirrors each command's `run()`: its failure-reporting format, then `execute`.
    private static func execute(_ command: ParsableCommand, context: Platform, console: GoldenConsole) async throws {
        switch command {
        case let command as ContainerCommand:
            let container = context.container
            try await container.commandRunner.run(format: command.reportFormat) {
                _ = try await command.execute(container)
            }
        case var command as XcrashlyticsCommand:
            // The bare root has no behavior of its own: ArgumentParser turns it into the help screen.
            try command.run()
        case is AsyncParsableCommand:
            preconditionFailure("golden harness has no route for \(type(of: command))")
        default:
            // `help <subcommand>` and friends: pure ArgumentParser, no context involved.
            var command = command
            try command.run()
        }
    }

    /// What `XcrashlyticsCommand.exit(withError:)` does, as data: help goes to
    /// stdout, usage errors to stderr, thrown exit codes print nothing.
    private static func finish(withError error: Error, console: GoldenConsole) -> Int32 {
        let code = XcrashlyticsCommand.exitCode(for: error)
        let text = XcrashlyticsCommand.fullMessage(for: error, columns: helpColumns)
        if !text.isEmpty {
            if code == .success {
                console.writeOutput(text + "\n")
            } else {
                console.writeDiagnostic(text + "\n")
            }
        }
        return code.rawValue
    }

    /// Machine-specific absolute paths replaced by stable placeholders.
    static func normalize(_ text: String) -> String {
        var result = text
        let cwd = FileManager.default.currentDirectoryPath
        let home = HomeDirectoryLocator.path
        for (path, placeholder) in [(cwd, "<CWD>"), (home, "<HOME>")].sorted(by: { $0.0.count > $1.0.count })
        where path.count > 1 {
            result = result.replacingOccurrences(of: path, with: placeholder)
        }
        return result
    }
}
