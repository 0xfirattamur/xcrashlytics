import ArgumentParser
import Foundation

@main
struct XcrashlyticsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcrashlytics",
        abstract:
            "Firebase Crashlytics from the terminal, with clean JSON for developers and AI agents.",
        version: "0.2.0",
        subcommands: [
            InitCommand.self,
            UseCommand.self,
            IssuesCommand.self,
            EventsCommand.self,
            ShowCommand.self,
            ExportCommand.self,
            OpenCommand.self,
            BlameCommand.self,
            GroupsCommand.self,
            BreakdownCommand.self,
        ]
    )

    static func main() async {
        StandardStreamConsole.ignoreBrokenPipeSignal()
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            var command = try parseReportingFailures(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    /// With `--format json|ndjson`, parse failures go through the error contract as BAD_INPUT/5 on stdout;
    /// otherwise (and for `--help`/`--version`) ArgumentParser's own handling applies.
    static func parseReportingFailures(
        _ arguments: [String],
        console: Console = StandardStreamConsole()
    ) throws -> ParsableCommand {
        do {
            return try parseAsRoot(arguments)
        } catch {
            guard let format = structuredFormat(in: arguments), exitCode(for: error) != .success else {
                throw error
            }
            let failure = badInputFailure(for: error)
            FailurePresenter(console: console).present(failure, format: format)
            throw ExitCode(failure.exitCode)
        }
    }

    /// The structured format (`json`/`ndjson`) the last `--format` in `arguments`
    /// asks for, or nil for text, an invalid value, or no `--format`.
    static func structuredFormat(in arguments: [String]) -> OutputFormat? {
        guard let requested = lastRequestedFormat(in: arguments),
              let format = OutputFormat(argument: requested),
              format.isJSON
        else { return nil }
        return format
    }

    private static func badInputFailure(for error: Error) -> CommandFailure {
        CommandFailure(
            code: "BAD_INPUT",
            exitCode: 5,
            message: message(for: error),
            hint: "Run: xcrashlytics --help")
    }

    /// The raw value of the last `--format <value>` or `--format=<value>`; everything after `--` is operands.
    private static func lastRequestedFormat(in arguments: [String]) -> String? {
        let flag = "--format"
        var requested: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { break }
            if argument == flag, index + 1 < arguments.count {
                requested = arguments[index + 1]
                index += 1
            } else if argument.hasPrefix(flag + "=") {
                requested = String(argument.dropFirst(flag.count + 1))
            }
            index += 1
        }
        return requested
    }
}
