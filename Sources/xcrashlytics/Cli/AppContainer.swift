/// Composition root: the only place that knows concrete types. Commands get services, never raw I/O.
struct AppContainer: Sendable {
    let platform: Platform
    let infrastructure: Infrastructure

    init(platform: Platform) {
        self.platform = platform
        self.infrastructure = Infrastructure(platform: platform)
    }

    static func production() -> AppContainer {
        AppContainer(platform: .production())
    }

    // MARK: - Output

    var commandRunner: CommandRunner {
        CommandRunner(console: platform.console)
    }

    var resultEmitter: ResultEmitter {
        ResultEmitter(console: platform.console)
    }

    // MARK: - Services

    var issueSearchService: IssueSearchService {
        IssueSearchService(sources: crashSources, dateProvider: platform.dateProvider)
    }

    var crashGroupingService: CrashGroupingService {
        CrashGroupingService(sources: crashSources, dateProvider: platform.dateProvider)
    }

    var eventQueryService: EventQueryService {
        EventQueryService(
            clients: infrastructure.crashlyticsClients,
            frameSelectors: frameSelectors,
            frameSymbolizer: infrastructure.frameSymbolizer,
            dateProvider: platform.dateProvider)
    }

    var crashDetailService: CrashDetailService {
        CrashDetailService(
            clients: infrastructure.crashlyticsClients,
            sources: crashSources,
            frameSelectors: frameSelectors,
            frameSymbolizer: infrastructure.frameSymbolizer,
            dateProvider: platform.dateProvider)
    }

    var crashExportService: CrashExportService {
        CrashExportService(
            details: crashDetailService,
            clients: infrastructure.crashlyticsClients,
            reportWriter: infrastructure.reportWriter,
            dateProvider: platform.dateProvider)
    }

    var crashOpenService: CrashOpenService {
        CrashOpenService(
            clients: infrastructure.crashlyticsClients,
            sources: crashSources,
            editor: infrastructure.editorLauncher,
            sourceFiles: infrastructure.sourceFileLister,
            dateProvider: platform.dateProvider,
            workingDirectory: platform.workingDirectory)
    }

    var breakdownService: BreakdownService {
        BreakdownService(clients: infrastructure.crashlyticsClients, dateProvider: platform.dateProvider)
    }

    var blameService: BlameService {
        BlameService(
            clients: infrastructure.crashlyticsClients,
            frameSelectors: frameSelectors,
            dateProvider: platform.dateProvider)
    }

    var profileSetupService: ProfileSetupService {
        ProfileSetupService(
            configRepository: infrastructure.configRepository,
            appDiscovery: infrastructure.appDiscovery,
            loginProbe: infrastructure.loginProbe,
            xcodeCrashes: infrastructure.xcodeCrashRepository,
            workingDirectory: platform.workingDirectory)
    }

    var profileSelectionService: ProfileSelectionService {
        ProfileSelectionService(configRepository: infrastructure.configRepository)
    }

    // MARK: - Shared collaborators

    private var crashSources: CrashSourceLoader {
        CrashSourceLoader(
            clients: infrastructure.crashlyticsClients,
            configRepository: infrastructure.configRepository,
            xcodeCrashRepository: infrastructure.xcodeCrashRepository)
    }

    private var frameSelectors: ProfileFrameSelector {
        ProfileFrameSelector(configRepository: infrastructure.configRepository)
    }
}
