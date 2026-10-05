//
//  FirebaseConsoleLinkTests.swift
//  xcrashlyticsTests
//

import Testing
@testable import xcrashlytics

@Suite("Firebase console link")
struct FirebaseConsoleLinkTests {
    /// Shape of a real link (firebase/firebase-ios-sdk#9737).
    private let link = "https://console.firebase.google.com/project/tata-one/crashlytics/app/ios:com.tatadigital.tcp"
        + "/issues/5ed6ac4e0f861660066a2f99181a0405?time=1649289600000:1650412799000"
        + "&sessionEventKey=ca5e0601db004a358cbbed734042db17_1662682800563319436"

    @Test("parses project, app, issue, and session event key")
    func parsesRealLink() throws {
        let parsed = try FirebaseConsoleLink(link)
        #expect(parsed.projectId == "tata-one")
        #expect(parsed.platform == "ios")
        #expect(parsed.bundleId == "com.tatadigital.tcp")
        #expect(parsed.issueId == "5ed6ac4e0f861660066a2f99181a0405")
        #expect(parsed.canonicalIssueId == "FB-5ed6ac4e0f861660066a2f99181a0405")
        #expect(parsed.candidateEventIds == [
            "ca5e0601db004a358cbbed734042db17_1662682800563319436",
            "ca5e0601db004a358cbbed734042db17",
        ])
    }

    @Test("issue link without an event key has no candidates")
    func issueOnlyLink() throws {
        let parsed = try FirebaseConsoleLink(
            "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues/I1")
        #expect(parsed.sessionEventKey == nil)
        #expect(parsed.candidateEventIds.isEmpty)
    }

    @Test(
        "rejects foreign hosts, plain http, and non-issue pages",
        arguments: [
            "https://evil.example.com/project/p/crashlytics/app/ios:com.x.app/issues/I1",
            "http://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues/I1",
            "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues",
            "https://console.firebase.google.com/project/p/overview",
            "https://console.firebase.google.com/project/p/crashlytics/app/com.x.app/issues/I1",
        ]
    )
    func rejectsInvalidLinks(_ value: String) {
        #expect(throws: FirebaseError.self) { try FirebaseConsoleLink(value) }
    }

    @Test("rejection messages never echo the link's query values")
    func rejectionDoesNotLeakQuery() {
        let secret = "https://evil.example.com/x?token=SECRET-123"
        do {
            _ = try FirebaseConsoleLink(secret)
            Issue.record("expected rejection")
        } catch {
            #expect(!String(describing: error).contains("SECRET-123"))
        }
    }

    // MARK: - app id resolution

    private func parsed(bundle: String) throws -> FirebaseConsoleLink {
        try FirebaseConsoleLink("https://console.firebase.google.com/project/p/crashlytics/app/ios:\(bundle)/issues/I1")
    }

    @Test("a profile matching the link's bundle id wins over the active profile")
    func matchingProfileWins() throws {
        let config = Config(activeProfile: "debug", profiles: [
            "debug": AppProfile(appId: "1:1:ios:debug", bundleId: "com.x.app.debug"),
            "release": AppProfile(appId: "1:1:ios:release", bundleId: "com.x.app"),
        ])
        #expect(config.appId(for: try parsed(bundle: "com.X.App")) == "1:1:ios:release")
    }

    @Test("matches the console link platform when bundle ids overlap")
    func matchingPlatformWins() throws {
        let config = Config(profiles: [
            "android": AppProfile(appId: "1:1:android:app", bundleId: "com.x.app"),
            "ios": AppProfile(appId: "1:1:ios:app", bundleId: "com.x.app"),
        ])
        let link = try FirebaseConsoleLink(
            "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues/I1")
        #expect(config.appId(for: link) == "1:1:ios:app")
    }

    @Test("an unknown bundle id is refused when the active app's bundle id is known")
    func refusesWrongApp() throws {
        let config = Config(activeProfile: "debug", profiles: [
            "debug": AppProfile(appId: "1:1:ios:debug", bundleId: "com.x.app.debug"),
        ])
        #expect(config.appId(for: try parsed(bundle: "com.other.app")) == nil)
    }

    @Test("falls back to the configured app when no bundle ids are recorded")
    func fallsBackWithoutBundleIds() throws {
        #expect(Config(appId: "1:1:ios:only").appId(for: try parsed(bundle: "com.any.app")) == "1:1:ios:only")
    }
}
