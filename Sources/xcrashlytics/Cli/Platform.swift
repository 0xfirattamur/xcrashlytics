import Foundation

struct Platform: Sendable {
    var fileStore: FileStore
    var subprocessExecutor: SubprocessExecutor
    var httpClient: HTTPClient
    var dateProvider: DateProvider
    var sleeper: Sleeper
    var console: Console
    var workingDirectory: String
    var homeDirectory: String

    static func production() -> Platform {
        Platform(
            fileStore: DiskFileStore(),
            subprocessExecutor: FoundationSubprocessExecutor(),
            httpClient: URLSessionHTTPClient(),
            dateProvider: SystemDateProvider(),
            sleeper: TaskSleeper(),
            console: StandardStreamConsole(),
            workingDirectory: FileManager.default.currentDirectoryPath,
            homeDirectory: HomeDirectoryLocator.path)
    }
}
