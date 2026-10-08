import Foundation
@testable import xcrashlytics

extension Platform {
    /// A platform on in-memory fakes; pass only what a test cares about.
    static func testing(
        fileStore: FileStore,
        subprocessExecutor: SubprocessExecutor,
        dateProvider: DateProvider,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        console: Console = StandardStreamConsole(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        homeDirectory: String = HomeDirectoryLocator.path
    ) -> Platform {
        Platform(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            httpClient: httpClient,
            dateProvider: dateProvider,
            sleeper: TaskSleeper(),
            console: console,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory)
    }

    var container: AppContainer { AppContainer(platform: self) }
}
