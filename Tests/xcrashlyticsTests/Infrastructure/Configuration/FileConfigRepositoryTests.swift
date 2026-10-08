import Foundation
import Testing
@testable import xcrashlytics

@Suite("FileConfigRepository")
struct FileConfigRepositoryTests {
    private var configPath: String {
        "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    }

    @Test("returns defaults when file missing")
    func returnsDefaultsWhenMissing() throws {
        let fileStore = InMemoryFileStore()
        let store = FileConfigRepository(fileStore: fileStore)
        let cfg = try store.load()
        #expect(cfg.appId == nil)
        #expect(cfg.activeProfile == nil)
        #expect(cfg.profiles.isEmpty)
    }

    @Test("saves and loads round trip")
    func roundTrip() throws {
        let fileStore = InMemoryFileStore()
        let store = FileConfigRepository(fileStore: fileStore)
        var cfg = Config()
        cfg.appId = "1:123:ios:abc"
        cfg.profiles["staging"] = AppProfile(appId: "1:456:ios:def", sourcePath: "Staging/GoogleService-Info.plist")
        cfg.activeProfile = "staging"
        try store.save(cfg)
        let loaded = try store.load()
        #expect(loaded.appId == "1:123:ios:abc")
        #expect(loaded.activeProfile == "staging")
        #expect(loaded.resolvedAppId == "1:456:ios:def")
        #expect(loaded.profiles["staging"]?.sourcePath == "Staging/GoogleService-Info.plist")
    }

    @Test("resolved app id falls back to root app id when profile is missing")
    func resolvedAppIdFallback() {
        let cfg = Config(appId: "1:123:ios:abc", activeProfile: "missing")
        #expect(cfg.resolvedAppId == "1:123:ios:abc")
    }

    @Test("reads and writes the config inside the injected working directory")
    func usesInjectedWorkingDirectory() throws {
        let fileStore = InMemoryFileStore()
        let store = FileConfigRepository(fileStore: fileStore, workingDirectory: "/project")
        try store.save(Config(appId: "1:123:ios:abc"))
        #expect(fileStore.exists(at: "/project/.xcrashlytics.json"))
        #expect(try store.load().appId == "1:123:ios:abc")
    }

    @Test("saved file ends with a newline and keeps slashes readable")
    func savedFileFormat() throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(profiles: [
            "debug": AppProfile(appId: "1:1:ios:a", sourcePath: "Debug/GoogleService-Info.plist"),
        ]))
        let text = try #require(String(data: try fileStore.readData(at: configPath), encoding: .utf8))
        #expect(text.hasSuffix("}\n"))
        #expect(!text.hasSuffix("\n\n"))
        #expect(text.contains("Debug/GoogleService-Info.plist"))
    }

    @Test("hand-edited mixed-case profile names stay reachable")
    func decodingLowercasesProfileNames() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: #"{"activeProfile":"Release","profiles":{"Release":{"appId":"1:2:ios:r"},"Debug":{"appId":"1:3:ios:d"}}}"#)
        let cfg = try FileConfigRepository(fileStore: fileStore).load()
        #expect(Set(cfg.profiles.keys) == ["release", "debug"])
        #expect(cfg.activeProfile == "release")
        #expect(cfg.resolvedAppId == "1:2:ios:r")
    }

    @Test("profile names that differ only by case make the file invalid, not a crash")
    func caseCollidingProfilesAreInvalid() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: #"{"profiles":{"Release":{"appId":"1:2:ios:r"},"release":{"appId":"1:3:ios:d"}}}"#)
        #expect(throws: ConfigError.invalidFile) { _ = try FileConfigRepository(fileStore: fileStore).load() }
    }

    @Test("corrupt file reports invalid configuration")
    func corruptReportsInvalidFile() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(configPath, text: "not json")
        let store = FileConfigRepository(fileStore: fileStore)
        #expect(throws: ConfigError.invalidFile) {
            _ = try store.load()
        }
    }
}

@Suite("Firebase app discovery")
struct FirebaseAppDiscovererTests {
    @Test("discovers iOS GoogleService plist app ids")
    func discoversIOSPlists() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/Debug/GoogleService-Info.plist", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>GOOGLE_APP_ID</key>
          <string>1:1111111111:ios:debug</string>
        </dict>
        </plist>
        """)
        fileStore.seed("/repo/Staging/GoogleService-Info.plist", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>GOOGLE_APP_ID</key>
          <string>1:2222222222:ios:staging</string>
        </dict>
        </plist>
        """)

        let apps = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo").apps

        #expect(apps.map(\.profileName) == ["debug", "staging"])
        #expect(apps.map(\.appId) == ["1:1111111111:ios:debug", "1:2222222222:ios:staging"])
    }

    @Test("discovers Android google-services app ids")
    func discoversAndroidJSON() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/app/google-services.json", text: """
        {
          "client": [
            {
              "client_info": {
                "mobilesdk_app_id": "1:3333333333:android:release"
              }
            }
          ]
        }
        """)

        let apps = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo").apps

        #expect(apps.map(\.profileName) == ["app"])
        #expect(apps.first?.platform == "android")
        #expect(apps.first?.appId == "1:3333333333:android:release")
    }

    @Test("reads iOS BUNDLE_ID and Android package_name")
    func discoversBundleIds() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/Release/GoogleService-Info.plist", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>GOOGLE_APP_ID</key><string>1:1111111111:ios:release</string>
          <key>BUNDLE_ID</key><string>com.x.app</string>
        </dict></plist>
        """)
        fileStore.seed("/repo/app/google-services.json", text: """
        {"client": [{"client_info": {
          "mobilesdk_app_id": "1:3333333333:android:release",
          "android_client_info": {"package_name": "com.x.android"}
        }}]}
        """)

        let apps = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo").apps

        #expect(Dictionary(uniqueKeysWithValues: apps.map { ($0.profileName, $0.bundleId) })
            == ["release": "com.x.app", "app": "com.x.android"])
    }

    @Test("a config file at the scan root gets the profile name 'default'")
    func rootLevelFileGetsDefaultName() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/GoogleService-Info.plist", text: """
        <plist version="1.0"><dict>
          <key>GOOGLE_APP_ID</key><string>1:1111111111:ios:root</string>
        </dict></plist>
        """)
        fileStore.seed("/repo/google-services.json", text: #"{"client":[{"client_info":{"mobilesdk_app_id":"1:3333333333:android:root"}}]}"#)

        let apps = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo").apps

        #expect(apps.map(\.profileName) == ["default", "default-2"])
    }

    @Test("malformed config files are skipped and reported, valid ones still found")
    func malformedFilesAreSkipped() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/Good/GoogleService-Info.plist", text: """
        <plist version="1.0"><dict>
          <key>GOOGLE_APP_ID</key><string>1:1111111111:ios:good</string>
        </dict></plist>
        """)
        fileStore.seed("/repo/Bad/GoogleService-Info.plist", text: "garbage not a plist")
        fileStore.seed("/repo/app/google-services.json", text: "{ not json")

        let result = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo")

        #expect(result.apps.map(\.profileName) == ["good"])
        #expect(Set(result.unreadable) == ["Bad/GoogleService-Info.plist", "app/google-services.json"])
    }

    @Test("a config file without a usable app id — a $(GOOGLE_APP_ID) template, a bare-string plist — is reported, not silently skipped")
    func configWithoutUsableAppIdIsReported() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/repo/Template/GoogleService-Info.plist", text: #"""
        <plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>$(FIREBASE_APP_ID)</string></dict></plist>
        """#)
        fileStore.seed("/repo/Bare/GoogleService-Info.plist", text: "garbage")
        fileStore.seed("/repo/app/google-services.json", text: #"{"client":[]}"#)
        let result = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo")
        #expect(result.apps.isEmpty)
        #expect(Set(result.unreadable) == [
            "Template/GoogleService-Info.plist", "Bare/GoogleService-Info.plist", "app/google-services.json"
        ])
    }

    @Test("keeps every discovered app when profile names collide")
    func keepsCollidingProfileNamesUnique() throws {
        let fileStore = InMemoryFileStore()
        for (index, path) in ["a/debug", "b/debug", "c/debug-2"].enumerated() {
            fileStore.seed("/repo/\(path)/GoogleService-Info.plist", text: """
            <plist version="1.0"><dict>
              <key>GOOGLE_APP_ID</key><string>1:\(1111111111 + index):ios:app</string>
            </dict></plist>
            """)
        }

        let apps = try FirebaseAppDiscoverer(fileStore: fileStore).discover(from: "/repo").apps
        #expect(Set(apps.map(\.profileName)).count == 3)
    }
}
