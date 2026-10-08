/// One concrete adapter per port, built once from the platform primitives.
struct Infrastructure: Sendable {
    let configRepository: ConfigRepository
    let crashlyticsClients: CrashlyticsClientProvider
    let xcodeCrashRepository: XcodeCrashRepository
    let frameSymbolizer: FrameSymbolizer
    let editorLauncher: EditorLauncher
    let appDiscovery: AppDiscovery
    let loginProbe: FirebaseLoginProbe
    let reportWriter: ReportWriter
    let sourceFileLister: SourceFileLister

    init(platform: Platform) {
        let fileStore = platform.fileStore
        let httpClient = platform.httpClient
        let dateProvider = platform.dateProvider
        let executor = platform.subprocessExecutor
        let makeTokenProvider: @Sendable () -> FirebaseToolsTokenProvider = {
            FirebaseToolsTokenProvider(fileStore: fileStore, httpClient: httpClient, dateProvider: dateProvider)
        }

        configRepository = FileConfigRepository(fileStore: fileStore, workingDirectory: platform.workingDirectory)
        // A fresh token provider per Crashlytics client, so each client keeps its own token cache.
        crashlyticsClients = RESTCrashlyticsClientProvider(
            configRepository: configRepository,
            httpClient: httpClient,
            sleeper: platform.sleeper,
            dateProvider: dateProvider,
            accessTokens: makeTokenProvider)
        xcodeCrashRepository = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: platform.homeDirectory)
        frameSymbolizer = DSYMSymbolicator(fileStore: fileStore, subprocessExecutor: executor)
        editorLauncher = XedEditorLauncher(subprocessExecutor: executor)
        appDiscovery = FirebaseAppDiscoverer(fileStore: fileStore)
        loginProbe = FirebaseToolsLoginProbe(subprocessExecutor: executor, tokens: makeTokenProvider())
        reportWriter = FileStoreReportWriter(fileStore: fileStore)
        sourceFileLister = FileStoreSourceFileLister(fileStore: fileStore)
    }
}
