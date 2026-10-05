import Foundation
import Testing
@testable import xcrashlytics

@Suite("loadXcodeCrashes")
struct XcodeCrashLoadingTests {
    /// Path `ConfigFile` reads: `<cwd>/.xcrashlytics.json`.
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    private var products: String {
        "\(NSString(string: "~").expandingTildeInPath)/Library/Developer/Xcode/Products"
    }

    private func context(fs: InMemoryFileSystem) -> CommandContext {
        CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: SystemClock(),
            httpTransport: MockHTTPTransport()
        )
    }

    private func report(bundleId: String, incident: String) throws -> String {
        let url = Bundle.module.url(forResource: "sample-symbolicated.crash", withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "com.example.ExampleApp", with: bundleId)
            .replacingOccurrences(of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", with: incident)
    }

    @Test("throws missingBundleId(nil) when no config exists")
    func throwsWithoutConfig() {
        let ctx = context(fs: InMemoryFileSystem())
        #expect(throws: ConfigError.missingBundleId(profile: nil)) {
            _ = try ctx.loadXcodeCrashes()
        }
    }

    @Test("throws missingBundleId(profile) when the active profile has no bundle id")
    func throwsWithoutBundleId() {
        let fs = InMemoryFileSystem()
        fs.seed(configPath, text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc"}}}"#)
        let ctx = context(fs: fs)
        #expect(throws: ConfigError.missingBundleId(profile: "dev")) {
            _ = try ctx.loadXcodeCrashes()
        }
    }

    @Test("explicit directories need no bundle id")
    func explicitDirectoriesSkipProfile() throws {
        let fs = InMemoryFileSystem()
        fs.seed("/reports/A.crash", text: try report(bundleId: "com.other.app", incident: "11111111-1111-1111-1111-111111111111"))
        let load = try context(fs: fs).loadXcodeCrashes(directories: ["/reports"])
        #expect(load.crashes.map(\.event.id) == ["XC-11111111-1111-1111-1111-111111111111"])
    }

    @Test("an extension profile finds its reports in the containing app's directory")
    func extensionReportsUnderContainingApp() throws {
        let fs = InMemoryFileSystem()
        fs.seed(configPath, text: #"{"activeProfile":"kb","profiles":{"kb":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app.keyboard"}}}"#)
        let appDirectory = "\(products)/com.example.app/Crashes"
        fs.seed("\(appDirectory)/ext.crash", text: try report(bundleId: "com.example.app.keyboard", incident: "11111111-1111-1111-1111-111111111111"))
        fs.seed("\(appDirectory)/app.crash", text: try report(bundleId: "com.example.app", incident: "22222222-2222-2222-2222-222222222222"))
        fs.seed(
            "\(products)/com.example/Crashes/org.crash",
            text: try report(bundleId: "com.example.app.keyboard", incident: "33333333-3333-3333-3333-333333333333"))

        let load = try context(fs: fs).loadXcodeCrashes()

        #expect(load.crashes.map(\.event.id) == ["XC-11111111-1111-1111-1111-111111111111"])
    }
}
