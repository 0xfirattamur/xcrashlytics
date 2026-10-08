import Foundation
import Testing
@testable import xcrashlytics

@Suite("CrashSourceLoader.xcodeCrashes")
struct CrashSourceLoaderXcodeCrashesTests {
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    private var products: String {
        "\(HomeDirectoryLocator.path)/Library/Developer/Xcode/Products"
    }

    private func loader(fileStore: InMemoryFileStore) -> CrashSourceLoader {
        let configRepository = FileConfigRepository(
            fileStore: fileStore, workingDirectory: FileManager.default.currentDirectoryPath)
        let clients = RESTCrashlyticsClientProvider(
            configRepository: configRepository,
            httpClient: FakeHTTPClient(),
            sleeper: TaskSleeper(),
            dateProvider: SystemDateProvider(),
            accessTokens: { StubAccessTokenProvider() })
        let xcodeCrashRepository = OrganizerCrashRepository(
            fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path)
        return CrashSourceLoader(
            clients: clients, configRepository: configRepository, xcodeCrashRepository: xcodeCrashRepository)
    }

    private func report(bundleId: String, incident: String) throws -> String {
        let url = Bundle.module.url(
            forResource: "sample-symbolicated.crash", withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "com.example.ExampleApp", with: bundleId)
            .replacingOccurrences(of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", with: incident)
    }

    @Test("throws missingBundleId(nil) when no config exists")
    func throwsWithoutConfig() {
        let loader = loader(fileStore: InMemoryFileStore())
        #expect(throws: ConfigError.missingBundleId(profile: nil)) {
            _ = try loader.xcodeCrashes(directories: [])
        }
    }

    @Test("throws missingBundleId(profile) when the active profile has no bundle id")
    func throwsWithoutBundleId() {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            configPath, text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc"}}}"#)
        let loader = loader(fileStore: fileStore)
        #expect(throws: ConfigError.missingBundleId(profile: "dev")) {
            _ = try loader.xcodeCrashes(directories: [])
        }
    }

    @Test("explicit directories need no bundle id")
    func explicitDirectoriesSkipProfile() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "/reports/A.crash",
            text: try report(bundleId: "com.other.app", incident: "11111111-1111-1111-1111-111111111111"))
        let load = try loader(fileStore: fileStore).xcodeCrashes(directories: ["/reports"])
        #expect(load.crashes.map(\.event.id) == ["XC-11111111-1111-1111-1111-111111111111"])
    }

    @Test("an extension profile finds its reports in the containing app's directory")
    func extensionReportsUnderContainingApp() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            configPath,
            text: #"{"activeProfile":"kb","profiles":{"kb":{"appId":"1:1234567890:ios:abc","#
                + #""bundleId":"com.example.app.keyboard"}}}"#)
        let appDirectory = "\(products)/com.example.app/Crashes"
        fileStore.seed(
            "\(appDirectory)/ext.crash",
            text: try report(bundleId: "com.example.app.keyboard", incident: "11111111-1111-1111-1111-111111111111"))
        fileStore.seed(
            "\(appDirectory)/app.crash",
            text: try report(bundleId: "com.example.app", incident: "22222222-2222-2222-2222-222222222222"))
        fileStore.seed(
            "\(products)/com.example/Crashes/org.crash",
            text: try report(bundleId: "com.example.app.keyboard", incident: "33333333-3333-3333-3333-333333333333"))

        let load = try loader(fileStore: fileStore).xcodeCrashes(directories: [])

        #expect(load.crashes.map(\.event.id) == ["XC-11111111-1111-1111-1111-111111111111"])
    }
}
