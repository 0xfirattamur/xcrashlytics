import Foundation
@testable import xcrashlytics

/// The deterministic environment a golden case runs in: configuration, login
/// state, installed tools, local crash reports and source files, all in memory.
struct GoldenWorld {
    enum ConfigState {
        /// `app` (active, `appLibraries: [KeyboardCore]`) and its extension `widget`.
        case twoProfiles
        /// No `.xcrashlytics.json` at all.
        case missing
        /// The file exists but is not valid JSON for the config schema.
        case invalidFile
        /// The active profile carries an app id the Crashlytics client rejects.
        case badAppId
        /// The active profile has no bundle id, so Xcode crash scanning cannot scope itself.
        case noBundleId
        /// A legacy top-level `appId` and no profiles.
        case appIdOnly
        /// Like `twoProfiles`, but the extension profile `widget` is active.
        case widgetActive
    }

    enum Login {
        case ok
        /// `firebase login` never ran: no firebase-tools config file.
        case missing
        /// Google answers `invalid_grant` for the stored refresh token.
        case revoked
        /// Google's token service answers 500.
        case tokenServiceDown
    }

    enum Sources {
        /// One `BlurService.swift` and one `ExampleViewController.swift` under the working directory.
        case unique
        case none
        /// A second `BlurService.swift`, so the file name resolves to two paths.
        case ambiguous
        /// A second `ExampleViewController.swift`, so a local crash's frames resolve to two paths.
        case ambiguousViewController
        /// The only copy of the file sits inside `.build`.
        case buildOutputOnly
    }

    var config = ConfigState.twoProfiles
    var login = Login.ok
    var firebaseCLIInstalled = true
    /// Exit code of `xed` and `open`.
    var launcherExitCode: Int32 = 0
    var sources = Sources.unique
    /// `GoogleService-Info.plist` files and an Xcode project for `init --scan`.
    var repoFiles = false
    /// With `repoFiles`: one more plist that is a template, not a real Firebase config.
    var brokenPlist = false
    var dsymTools = DsymTools.working
    /// `reports/<name>` endpoints that answer 500 (`topVersions`, `topOperatingSystems`, `topAppleDevices`).
    var failingReports: Set<String> = []
    /// Issues whose `events` listing answers 500.
    var failingEventIssues: Set<String> = []
    /// `topIssues` never runs out of pages, so an issue outside the ranking is never reached.
    var endlessIssuePages = false
    var fileFault = GoldenFileStore.Fault.none

    enum DsymTools {
        case working
        case atosFails
        case otoolFails
    }

    /// 2026-06-15T12:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_781_524_800)
    static let appId = "1:1234567890:ios:aaaa1111bbbb2222"
    static let widgetAppId = "1:1234567890:ios:cccc3333dddd4444"
    static let crashDirectory = "/crashes"
    static let mixedCrashDirectory = "/crashes-mixed"
    static let rawCrashDirectory = "/crashes-raw"
    static let dsymDirectory = "/dsyms"
    static let noFramesCrashDirectory = "/crashes-noframes"

    struct Built {
        var context: Platform
        /// Files created or changed since the world was built, by path.
        var writtenFiles: () -> [String: String]
        /// `METHOD url` of each request sent so far, sorted.
        var requests: () -> [String]
    }

    func build(console: Console) -> Built {
        let files = InMemoryFileStore()
        seedConfig(into: files)
        seedLogin(into: files)
        seedCrashReports(into: files)
        seedSources(into: files)
        seedDsyms(into: files)
        if repoFiles {
            GoldenRepoFixtures.seed(into: files, root: FileManager.default.currentDirectoryPath, brokenPlist: brokenPlist)
        }
        let baseline = snapshot(files)

        let world = self
        let httpClient = FakeHTTPClient { request in try GoldenAPI.respond(to: request, in: world) }
        let context = Platform.testing(
            fileStore: GoldenFileStore(base: files, fault: fileFault, configPath: configPath),
            subprocessExecutor: subprocessExecutor(),
            dateProvider: FixedDateProvider(Self.now),
            httpClient: httpClient,
            console: console
        )
        return Built(context: context, writtenFiles: {
            let current = snapshot(files)
            return current.filter { baseline[$0.key] != $0.value }
        }, requests: {
            httpClient.requests.map { "\($0.httpMethod ?? "GET") \($0.url?.absoluteString ?? "")" }.sorted()
        })
    }

    private func snapshot(_ files: InMemoryFileStore) -> [String: String] {
        var result: [String: String] = [:]
        for path in files.snapshotPaths() {
            result[path] = (try? files.readData(at: path)).flatMap { String(data: $0, encoding: .utf8) } ?? "<binary>"
        }
        return result
    }

    // MARK: - Seeding

    private var configPath: String { "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json" }

    private func seedConfig(into files: InMemoryFileStore) {
        switch config {
        case .missing:
            break
        case .invalidFile:
            files.seed(configPath, text: "{ this is not json")
        case .twoProfiles, .widgetActive:
            save(Config(activeProfile: config == .widgetActive ? "widget" : "app", profiles: [
                "app": AppProfile(
                    appId: Self.appId, bundleId: "com.example.app",
                    sourcePath: "App/GoogleService-Info.plist", appLibraries: ["KeyboardCore"]),
                "widget": AppProfile(
                    appId: Self.widgetAppId, bundleId: "com.example.app.widget",
                    sourcePath: "Widget/GoogleService-Info.plist", appLibraries: ["KeyboardCore"], extensionOf: "app"),
            ]), into: files)
        case .badAppId:
            save(Config(activeProfile: "app", profiles: ["app": AppProfile(appId: "not-an-app-id", bundleId: "com.example.app")]), into: files)
        case .noBundleId:
            save(Config(activeProfile: "app", profiles: ["app": AppProfile(appId: Self.appId)]), into: files)
        case .appIdOnly:
            save(Config(appId: Self.appId), into: files)
        }
    }

    private func save(_ config: Config, into files: InMemoryFileStore) {
        // The store only fails on an unwritable path, which an in-memory store never is.
        try? FileConfigRepository(fileStore: files).save(config)
    }

    private func seedLogin(into files: InMemoryFileStore) {
        guard login != .missing else { return }
        files.seed(FirebaseToolsTokenProvider.defaultConfigPath(), text: #"{"tokens":{"refresh_token":"golden-refresh-token"}}"#)
    }

    private func seedCrashReports(into files: InMemoryFileStore) {
        let modificationDate = { (day: Int) in Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400) }
        let organizer = "\(HomeDirectoryLocator.path)/Library/Developer/Xcode/Products/com.example.app/Crashes/Points/A.xccrashpoint/Logs"
        let crashes = GoldenCrashFixtures.self
        files.seed("\(organizer)/sample.crash", text: crashes.text("sample.crash"), modificationDate: modificationDate(1))
        files.seed("\(organizer)/ips-crash.ips", text: crashes.text("ips-crash.ips"), modificationDate: modificationDate(2))
        let widgetCrash = crashes.text("sample.crash")
            .replacingOccurrences(of: "com.example.ExampleApp", with: "com.example.app.widget")
            .replacingOccurrences(of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", with: "77777777-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        files.seed("\(organizer)/widget.crash", text: widgetCrash, modificationDate: modificationDate(3))
        files.seed("\(Self.crashDirectory)/sample-symbolicated.crash", text: crashes.text("sample-symbolicated.crash"), modificationDate: modificationDate(1))
        files.seed("\(Self.crashDirectory)/ips-crash.ips", text: crashes.text("ips-crash.ips"), modificationDate: modificationDate(2))
        files.seed(
            "\(Self.mixedCrashDirectory)/sample-symbolicated.crash",
            text: crashes.text("sample-symbolicated.crash"),
            modificationDate: modificationDate(1)
        )
        files.seed("\(Self.mixedCrashDirectory)/ips-hang.ips", text: crashes.text("ips-hang.ips"), modificationDate: modificationDate(2))
        files.seed("\(Self.mixedCrashDirectory)/malformed.crash", text: crashes.text("malformed.crash"), modificationDate: modificationDate(3))
        files.seed("\(Self.mixedCrashDirectory)/ips-corrupt.ips", text: crashes.text("ips-corrupt.ips"), modificationDate: modificationDate(4))
        files.seed("\(Self.rawCrashDirectory)/unsymbolicated.crash", text: crashes.text("unsymbolicated.crash"), modificationDate: modificationDate(1))
        files.seed("\(Self.noFramesCrashDirectory)/noframes.crash", text: GoldenCrashFixtures.noFrames, modificationDate: modificationDate(1))
    }

    private func seedSources(into files: InMemoryFileStore) {
        let cwd = FileManager.default.currentDirectoryPath
        let code = Data("// source\n".utf8)
        switch sources {
        case .none:
            break
        case .unique, .ambiguous, .ambiguousViewController:
            files.seed("\(cwd)/Sources/BlurService.swift", data: code)
            files.seed("\(cwd)/Sources/ExampleViewController.swift", data: code)
            if sources == .ambiguous { files.seed("\(cwd)/Other/BlurService.swift", data: code) }
            if sources == .ambiguousViewController { files.seed("\(cwd)/Other/ExampleViewController.swift", data: code) }
        case .buildOutputOnly:
            files.seed("\(cwd)/.build/checkouts/BlurService.swift", data: code)
        }
    }

    private func seedDsyms(into files: InMemoryFileStore) {
        let dwarf = "\(Self.dsymDirectory)/KeyboardCore.framework.dSYM/Contents/Resources/DWARF"
        files.seed("\(dwarf)/KeyboardCore", data: Data([0]))
        files.seed("\(Self.dsymDirectory)/__MACOSX/KeyboardCore.framework.dSYM/Contents/Resources/DWARF/KeyboardCore", data: Data([0]))
        files.seed("/empty-dsyms/readme.txt", data: Data([0]))
    }

    // MARK: - Subprocesses

    private func subprocessExecutor() -> StubSubprocessExecutor {
        let world = self
        return StubSubprocessExecutor { executable, arguments in
            switch (executable, arguments.first) {
            case ("/usr/bin/env", "which"):
                return world.firebaseCLIInstalled
                    ? SubprocessResult(exitCode: 0, standardOutput: "/usr/local/bin/firebase\n", standardError: "")
                    : SubprocessResult(exitCode: 1, standardOutput: "", standardError: "")
            case ("/usr/bin/env", "xed"):
                return world.launch(tool: "xed")
            case ("/usr/bin/open", _):
                return world.launch(tool: "open")
            case ("/usr/bin/xcrun", "otool"):
                return world.dsymTools == .otoolFails
                    ? SubprocessResult(exitCode: 1, standardOutput: "", standardError: "otool: file is not a Mach-O")
                    : SubprocessResult(exitCode: 0, standardOutput: GoldenDsymFixtures.otoolOutput, standardError: "")
            case ("/usr/bin/xcrun", "atos"):
                return world.dsymTools == .atosFails
                    ? SubprocessResult(exitCode: 1, standardOutput: "", standardError: "atos: cannot load symbols")
                    : SubprocessResult(exitCode: 0, standardOutput: GoldenDsymFixtures.atosOutput(for: arguments), standardError: "")
            default:
                return nil
            }
        }
    }

    private func launch(tool: String) -> SubprocessResult {
        launcherExitCode == 0
            ? SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
            : SubprocessResult(exitCode: launcherExitCode, standardOutput: "", standardError: "\(tool): launch failed")
    }
}

/// Reads the shared crash report samples next to the unit tests.
enum GoldenCrashFixtures {
    /// A legacy report with a header but no thread sections.
    static let noFrames = """
    Incident Identifier: 11111111-2222-3333-4444-555555555555
    Hardware Model:      iPhone14,2
    Process:             ExampleApp [1234]
    Identifier:          com.example.ExampleApp
    Version:             1 (1.0)
    Date/Time:           2026-05-02 10:00:00.000 +0000
    OS Version:          iPhone OS 17.0 (21A329)
    Exception Type:  EXC_BAD_ACCESS (SIGSEGV)
    Triggered by Thread:  0

    """

    static func text(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

enum GoldenDsymFixtures {
    static let otoolOutput = """
    Load command 0
         cmd LC_UUID
     cmdsize 24
        uuid B0B2532E-E644-3C37-BC05-42B715648E19
    Load command 1
          cmd LC_SEGMENT_64
      cmdsize 72
      segname __PAGEZERO
       vmaddr 0x0000000000000000
       vmsize 0x0000000100000000
    Load command 2
          cmd LC_SEGMENT_64
      cmdsize 2072
      segname __TEXT
       vmaddr 0x0000000100000000
       vmsize 0x00000000003a4000
    """

    /// One line per requested address: the blame address resolves, the rest echo back unresolved.
    static func atosOutput(for arguments: [String]) -> String {
        let resolved = "BlurKernel.run() (in KeyboardCore) (BlurKernel.swift:112)"
        let lines = arguments.drop { $0 != "-l" }.dropFirst(2).map { $0 == "0x1001fed74" ? resolved : $0 }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Firebase config files and an Xcode project, for `init --scan`.
enum GoldenRepoFixtures {
    static func seed(into files: InMemoryFileStore, root: String, brokenPlist: Bool) {
        if brokenPlist {
            let template = #"<plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>$(GOOGLE_APP_ID)</string></dict></plist>"#
            files.seed("\(root)/Broken/GoogleService-Info.plist", text: template)
        }
        plist(files, "\(root)/App/GoogleService-Info.plist", appId: GoldenWorld.appId, bundleId: "com.example.app")
        plist(files, "\(root)/Widget/GoogleService-Info.plist", appId: GoldenWorld.widgetAppId, bundleId: "com.example.app.widget")
        plist(files, "\(root)/Pods/Vendored/GoogleService-Info.plist", appId: "1:1234567890:ios:eeee5555ffff6666", bundleId: "com.vendored")
        files.seed("\(root)/App/App.xcodeproj/project.pbxproj", text: pbxproj)
    }

    private static func plist(_ files: InMemoryFileStore, _ path: String, appId: String, bundleId: String) {
        files.seed(path, text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>\(appId)</string>\
        <key>BUNDLE_ID</key><string>\(bundleId)</string></dict></plist>
        """)
    }

    private static let pbxproj = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tobjects = {
    \t\tT1 = {isa = PBXNativeTarget; name = KeyboardCore; productName = KeyboardCore; productType = "com.apple.product-type.framework";};
    \t\tT2 = {isa = PBXNativeTarget; name = Imaging; productName = Imaging; productType = "com.apple.product-type.library.static";};
    \t\tT3 = {isa = PBXNativeTarget; name = App; productName = App; productType = "com.apple.product-type.application";};
    \t};
    \trootObject = T3;
    }
    """
}
