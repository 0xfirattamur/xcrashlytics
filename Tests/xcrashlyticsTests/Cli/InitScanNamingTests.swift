import Foundation
import Testing
@testable import xcrashlytics

/// `init --scan`: profile names from bundle ids, extensions, and first-party library detection.
@Suite("xcrashlytics init --scan naming and libraries")
struct InitScanNamingTests {
    private var cwd: String { FileManager.default.currentDirectoryPath }
    private let framework = "com.apple.product-type.framework"
    private let unitTest = "com.apple.product-type.bundle.unit-test"
    private let staticLib = "com.apple.product-type.library.static"
    private let appExtension = "com.apple.product-type.app-extension"

    private func context(_ fileStore: InMemoryFileStore) -> Platform {
        fileStore.seed("\(HomeDirectoryLocator.path)/.config/configstore/firebase-tools.json", text: #"{"tokens":{"refresh_token":"R"}}"#)
        let httpClient = FakeHTTPClient { _ in
            FakeHTTPClient.response(
                FirebaseToolsTokenProvider.tokenEndpoint, status: 200,
                body: Data(#"{"access_token":"ya29.x","expires_in":3599}"#.utf8))
        }
        let subprocessExecutor = StubSubprocessExecutor { _, args in
            args == ["which", "firebase"] ? SubprocessResult(exitCode: 0, standardOutput: "/usr/local/bin/firebase\n", standardError: "") : nil
        }
        return Platform.testing(
            fileStore: fileStore, subprocessExecutor: subprocessExecutor, dateProvider: SystemDateProvider(), httpClient: httpClient, console: SpyConsole())
    }

    private func seedPlist(_ fileStore: InMemoryFileStore, _ relative: String, appId: String, bundleId: String) {
        fileStore.seed("\(cwd)/\(relative)", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>\(appId)</string>\
        <key>BUNDLE_ID</key><string>\(bundleId)</string></dict></plist>
        """)
    }

    /// The two plists of a keyboard app: the app and its keyboard extension.
    private func seedKeyboardApp(_ fileStore: InMemoryFileStore) {
        seedPlist(fileStore, "ai-keyboard/Supporting Files/GoogleService-Info.plist",
                  appId: "1:1111111111:ios:app", bundleId: "com.example.Keyboard")
        seedPlist(fileStore, "custom-keyboard/SupportingFiles/GoogleService-Info.plist",
                  appId: "1:1111111111:ios:ext", bundleId: "com.example.Keyboard.custom-keyboard")
    }

    private func pbxproj(_ targets: String) -> String {
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjects = {\n\(targets)\n\t};\n\trootObject = A1;\n}\n"
    }

    @Test("an extension is named by its bundle-id suffix and points at the app, which is named `app`")
    func extensionNaming() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)

        let output = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["app", "custom-keyboard"])
        #expect(config.profiles["app"]?.appId == "1:1111111111:ios:app")
        #expect(config.profiles["app"]?.extensionOf == nil)
        let keyboard = try #require(config.profiles["custom-keyboard"])
        #expect(keyboard.appId == "1:1111111111:ios:ext")
        #expect(keyboard.bundleId == "com.example.Keyboard.custom-keyboard")
        #expect(keyboard.extensionOf == "app")
        #expect(output.contains("extension of app"))
        // Two apps: nothing is guessed.
        #expect(config.activeProfile == nil)
    }

    @Test("an app that is not the only root gets its last bundle component when `app` is taken")
    func secondRootFallsBackToLastComponent() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)
        seedPlist(fileStore, "Other/GoogleService-Info.plist", appId: "1:1111111111:ios:other", bundleId: "com.example.Notes")
        seedPlist(fileStore, "OtherWidget/GoogleService-Info.plist", appId: "1:1111111111:ios:widget", bundleId: "com.example.Notes.widget")

        _ = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["app", "custom-keyboard", "notes", "widget"])
        #expect(config.profiles["notes"]?.appId == "1:1111111111:ios:other")
        #expect(config.profiles["widget"]?.extensionOf == "notes")
        #expect(config.profiles["custom-keyboard"]?.extensionOf == "app")
    }

    @Test("several config files sharing one bundle id stay environments named by folder")
    func environmentsKeepFolderNames() async throws {
        let fileStore = InMemoryFileStore()
        seedPlist(fileStore, "Debug/GoogleService-Info.plist", appId: "1:1111111111:ios:debug", bundleId: "com.example.app")
        seedPlist(fileStore, "Release/GoogleService-Info.plist", appId: "1:1111111111:ios:release", bundleId: "com.example.app")
        seedPlist(fileStore, "Widget/GoogleService-Info.plist", appId: "1:1111111111:ios:widget", bundleId: "com.example.app.widget")

        _ = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["debug", "release", "widget"])
        #expect(config.profiles["widget"]?.extensionOf == "debug")
    }

    @Test("without any extension relation the folder names stay")
    func unrelatedAppsKeepFolderNames() async throws {
        let fileStore = InMemoryFileStore()
        seedPlist(fileStore, "Notes/GoogleService-Info.plist", appId: "1:1111111111:ios:notes", bundleId: "com.example.notes")
        seedPlist(fileStore, "Chat/GoogleService-Info.plist", appId: "1:1111111111:ios:chat", bundleId: "com.example.chat")

        _ = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        #expect(Set(try FileConfigRepository(fileStore: fileStore).load().profiles.keys) == ["notes", "chat"])
    }

    @Test("re-scanning keeps the names of an existing config's profiles and adds extensionOf under them")
    func rescanKeepsExistingNames() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)
        try FileConfigRepository(fileStore: fileStore).save(Config(activeProfile: "supportingfiles", profiles: [
            "supporting files": AppProfile(appId: "1:1111111111:ios:app", bundleId: "com.example.Keyboard"),
            "supportingfiles": AppProfile(appId: "1:1111111111:ios:ext", bundleId: "com.example.Keyboard.custom-keyboard"),
        ]))

        _ = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(config.profiles.keys) == ["supporting files", "supportingfiles"])
        #expect(config.activeProfile == "supportingfiles")
        #expect(config.profiles["supportingfiles"]?.extensionOf == "supporting files")
        #expect(config.profiles["supporting files"]?.extensionOf == nil)
    }

    // MARK: - Libraries

    @Test("--scan records the repo's framework and static-library targets, by product name, but not Pods or tests")
    func scanDetectsLibraries() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)
        fileStore.seed("\(cwd)/App.xcodeproj/project.pbxproj", text: pbxproj("""
        \t\tA1 = {isa = PBXNativeTarget; name = App; productName = App; productType = "com.apple.product-type.application";};
        \t\tA2 = {isa = PBXNativeTarget; name = KeyboardCore; productName = KeyboardCore; productType = "\(framework)";};
        \t\tA3 = {isa = PBXNativeTarget; name = KeyboardCoreTests; productName = KeyboardCoreTests; productType = "\(unitTest)";};
        \t\tA4 = {isa = PBXNativeTarget; name = Util; productName = "$(TARGET_NAME)"; productReference = A5; productType = "\(staticLib)";};
        \t\tA5 = {isa = PBXFileReference; path = libUtilKit.a;};
        \t\tA6 = {isa = PBXNativeTarget; name = Widget; productName = Widget; productType = "\(appExtension)";};
        """))
        fileStore.seed("\(cwd)/Pods/Pods.xcodeproj/project.pbxproj", text: pbxproj("""
        \t\tP1 = {isa = PBXNativeTarget; name = Firebase; productName = Firebase; productType = "com.apple.product-type.framework";};
        """))

        let output = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(config.profiles["app"]?.appLibraries == ["KeyboardCore", "UtilKit"])
        #expect(config.profiles["custom-keyboard"]?.appLibraries == ["KeyboardCore", "UtilKit"])
        #expect(output.contains("First-party libraries: KeyboardCore, UtilKit"))
    }

    @Test("a project that does not parse contributes no libraries and does not fail the scan")
    func unparseableProject() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)
        fileStore.seed("\(cwd)/App.xcodeproj/project.pbxproj", text: "not a project {{{")

        _ = try await InitCommand.parse(["--scan"]).execute(context(fileStore).container)

        #expect(try FileConfigRepository(fileStore: fileStore).load().profiles["app"]?.appLibraries == nil)
    }

    @Test("--app-library sets the profile's libraries; a re-run without it keeps them")
    func manualAppLibraries() async throws {
        let fileStore = InMemoryFileStore()
        let ctx = context(fileStore)

        _ = try await InitCommand.parse([
            "--app-id", "1:1234567890:ios:abcdef", "--profile", "kb",
            "--app-library", "KeyboardCore", "--app-library", "Engine", "--app-library", "keyboardcore",
        ]).execute(ctx.container)
        #expect(try FileConfigRepository(fileStore: fileStore).load().profiles["kb"]?.appLibraries == ["Engine", "KeyboardCore"])
        #expect(try FileConfigRepository(fileStore: fileStore).load().resolvedAppLibraries == ["engine", "keyboardcore"])

        _ = try await InitCommand.parse(["--app-id", "1:1234567890:ios:abcdef", "--profile", "kb"]).execute(ctx.container)
        #expect(try FileConfigRepository(fileStore: fileStore).load().profiles["kb"]?.appLibraries == ["Engine", "KeyboardCore"])
    }

    @Test("--scan merges explicit --app-library values with detected and existing ones")
    func scanMergesAppLibraries() async throws {
        let fileStore = InMemoryFileStore()
        seedKeyboardApp(fileStore)
        fileStore.seed("\(cwd)/App.xcodeproj/project.pbxproj", text: pbxproj("""
        \t\tA2 = {isa = PBXNativeTarget; name = KeyboardCore; productName = KeyboardCore; productType = "com.apple.product-type.framework";};
        """))
        try FileConfigRepository(fileStore: fileStore).save(Config(profiles: [
            "app": AppProfile(appId: "1:1111111111:ios:app", appLibraries: ["Manual"]),
        ]))

        _ = try await InitCommand.parse(["--scan", "--app-library", "Extra"]).execute(context(fileStore).container)

        let config = try FileConfigRepository(fileStore: fileStore).load()
        #expect(config.profiles["app"]?.appLibraries == ["Extra", "KeyboardCore", "Manual"])
    }

    @Test("an empty --app-library is BAD_INPUT")
    func emptyAppLibrary() async throws {
        let cmd = try InitCommand.parse(["--app-id", "1:1:ios:x", "--profile", "kb", "--app-library", " "])
        let error = await #expect(throws: (any Error).self) { _ = try await cmd.execute(context(InMemoryFileStore()).container) }
        #expect(CommandRunner.failure(for: try #require(error)).code == "BAD_INPUT")
    }

    @Test("profile libraries and extensionOf round-trip through the config file, and stay absent when unset")
    func configRoundTrip() throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(activeProfile: "kb", profiles: [
            "kb": AppProfile(appId: "1:1:ios:x", appLibraries: ["KeyboardCore"], extensionOf: "app"),
            "app": AppProfile(appId: "1:1:ios:y"),
        ]))
        let loaded = try FileConfigRepository(fileStore: fileStore).load()
        #expect(loaded.profiles["kb"]?.appLibraries == ["KeyboardCore"])
        #expect(loaded.profiles["kb"]?.extensionOf == "app")
        let text = try #require(String(bytes: try fileStore.readData(at: "\(cwd)/.xcrashlytics.json"), encoding: .utf8))
        #expect(text.components(separatedBy: "appLibraries").count == 2)
        #expect(text.components(separatedBy: "extensionOf").count == 2)
    }
}
