import ArgumentParser

@main
struct XcrashlyticsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcrashlytics",
        abstract:
            "Firebase Crashlytics from the terminal, with clean JSON for developers and AI agents.",
        version: "0.1.0",
        subcommands: [
            InitCommand.self,
            UseCommand.self,
            IssuesCommand.self,
            EventsCommand.self,
            ShowCommand.self,
            OpenCommand.self,
            BlameCommand.self,
            GroupsCommand.self,
        ]
    )
}
