import Foundation

/// Production wiring of every protocol-shaped dependency the CLI needs.
///
/// Commands take a `CommandContext` instead of constructing their own dependencies
/// so tests can hand them an alternate context backed by in-memory fakes.
struct CommandContext: Sendable {
    let fileSystem: FileSystem
    let processRunner: ProcessRunner
    let clock: Clock
    let console: CLIConsole
    let httpTransport: HTTPTransport

    init(
        fileSystem: FileSystem,
        processRunner: ProcessRunner,
        clock: Clock,
        httpTransport: HTTPTransport = URLSessionHTTPTransport(),
        console: CLIConsole = StandardConsole()
    ) {
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.clock = clock
        self.httpTransport = httpTransport
        self.console = console
    }

    static func live() -> CommandContext {
        CommandContext(
            fileSystem: DiskFileSystem(),
            processRunner: ShellProcessRunner(),
            clock: SystemClock()
        )
    }

    func crashlyticsClient(appId override: String? = nil) throws -> CrashlyticsAPI {
        let config = try ConfigFile(fileSystem: fileSystem).load()
        guard let appId = override ?? config.resolvedAppId else {
            throw ConfigError.missingAppId
        }
        return try CrashlyticsClient(
            appId: appId,
            fileSystem: fileSystem,
            httpTransport: httpTransport
        )
    }
}
