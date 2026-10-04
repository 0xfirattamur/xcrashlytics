import Foundation
import Testing
@testable import XCrashlyticsCore
import XCrashlyticsTestSupport
@testable import xcrashlytics

@Suite("xcodeCrashDirectories")
struct XcodeCrashLoadingTests {
    /// Path `ConfigFile` reads: `<cwd>/.xcrashlytics.json`.
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    private func context(fs: InMemoryFileSystem) -> CommandContext {
        CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: SystemClock(),
            httpClient: MockHTTPClient()
        )
    }

    @Test("throws missingBundleId(nil) when no config exists")
    func throwsWithoutConfig() {
        let ctx = context(fs: InMemoryFileSystem())
        #expect(throws: ConfigError.missingBundleId(profile: nil)) {
            _ = try ctx.xcodeCrashDirectories()
        }
    }

    @Test("throws missingBundleId(profile) when the active profile has no bundle id")
    func throwsWithoutBundleId() {
        let fs = InMemoryFileSystem()
        fs.seed(configPath, text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc"}}}"#)
        let ctx = context(fs: fs)
        #expect(throws: ConfigError.missingBundleId(profile: "dev")) {
            _ = try ctx.xcodeCrashDirectories()
        }
    }

    @Test("returns the single scoped Products directory when configured")
    func returnsScopedDirectory() throws {
        let fs = InMemoryFileSystem()
        fs.seed(configPath, text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#)
        let ctx = context(fs: fs)
        let dirs = try ctx.xcodeCrashDirectories()
        let home = NSString(string: "~").expandingTildeInPath
        #expect(dirs == ["\(home)/Library/Developer/Xcode/Products/com.example.app"])
    }
}
