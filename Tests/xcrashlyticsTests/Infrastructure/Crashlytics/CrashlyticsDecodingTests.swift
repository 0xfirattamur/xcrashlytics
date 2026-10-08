import Foundation
import Testing
@testable import xcrashlytics

@Suite("Firebase DTO decoding")
struct CrashlyticsDecodingTests {
    private func eventDTO(_ json: String) throws -> CrashlyticsDTO.Event {
        try JSONDecoder().decode(CrashlyticsDTO.Event.self, from: Data(json.utf8))
    }

    @Test("a live-shaped non-fatal event: thread blamed flag, errors[], issue object, resource name")
    func liveShapedEvent() throws {
        let json = #"""
        {
          "name": "projects/1/apps/1:1:ios:a/events/ed6f07f2d0a4439c956f613c839aaf95_2272339782204297885",
          "eventId": "2272339782204297885",
          "issue": {"id": "3c2d", "title": "[Core] FIRCLSNonFatalError.m", "subtitle": "com.apple.CoreML (0) - Failed", "errorType": "NON_FATAL"},
          "blameFrame": {
            "line": "33", "file": "FIRCLSNonFatalError.m", "symbol": "-[FIRCLSNonFatalError init]",
            "offset": "33", "address": "2744580", "library": "Core", "owner": "THIRD_PARTY", "blamed": true
          },
          "errors": [{"title": "Non-fatal: Error", "subtitle": "Domain: com.apple.CoreML", "blamed": true, "frames": [{"symbol": "e", "address": "1"}]}],
          "threads": [{"title": "Thread", "blamed": true, "frames": [{"symbol": "t"}]}]
        }
        """#
        let event = try CrashlyticsEventDTOMapper().event(from: eventDTO(json))
        #expect(event.eventId == "2272339782204297885")
        #expect(event.resourceName == "ed6f07f2d0a4439c956f613c839aaf95_2272339782204297885")
        #expect(event.issueId == "3c2d")
        #expect(event.issueTitle == "[Core] FIRCLSNonFatalError.m")
        #expect(event.issueSubtitle == "com.apple.CoreML (0) - Failed")
        #expect(event.blameFrame?.address == 2_744_580)
        #expect(event.blameFrame?.offset == "33")
        #expect(event.threads.map(\.blamed) == [true])
        #expect(event.errors.count == 1)
        #expect(event.errors[0].blamed)
        #expect(event.errors[0].frames.first?.address == 1)
    }

    @Test("int64 fields accept numbers, numeric strings, and tolerate garbage")
    func flexibleInts() throws {
        let event = try CrashlyticsEventDTOMapper().event(from: eventDTO(#"""
        {"memory":{"free":"10","used":20},"storage":{"free":"x","used":null},
         "threads":[{"frames":[{"line":7},{"line":"8"},{"line":"nine"},{"line":null}]}]}
        """#))
        #expect(event.memoryFree == 10)
        #expect(event.memoryUsed == 20)
        #expect(event.storageFree == nil)
        #expect(event.storageUsed == nil)
        #expect(event.threads[0].frames.map(\.line) == [7, 8, nil, nil])
    }

    @Test("issue maps state, errorType, first signal, and falls back from title for the type")
    func issueMapping() throws {
        let issue = try CrashlyticsIssueMapper().issue(from: JSONDecoder().decode(CrashlyticsDTO.Issue.self, from: Data(#"""
        {"id":"I1","title":"T","errorType":"ANR","state":"CLOSED","uri":"https://console.example/x",
         "signals":[{"signal":"SIGNAL_REGRESSED"},{"signal":"SIGNAL_FRESH"}]}
        """#.utf8)))
        #expect(issue.state == "CLOSED")
        #expect(issue.errorType == "ANR")
        #expect(issue.exceptionType == "ANR")
        #expect(issue.signal == "SIGNAL_REGRESSED")
        #expect(issue.consoleURL == "https://console.example/x")

        let bare = try CrashlyticsIssueMapper().issue(from: JSONDecoder().decode(CrashlyticsDTO.Issue.self, from: Data(#"{"id":"I2","title":"Boom"}"#.utf8)))
        #expect(bare.exceptionType == "Boom")
        #expect(bare.errorType == nil)
        #expect(bare.state == nil)
    }

    @Test("issue id handling is case-insensitive about the FB- prefix")
    func issueIdPrefix() {
        #expect(CrashlyticsIdFormatter.issueId(from: "fb-abc") == "abc")
        #expect(CrashlyticsIdFormatter.issueId(from: "FB-abc") == "abc")
        #expect(CrashlyticsIdFormatter.issueId(from: "abc") == "abc")
        #expect(CrashlyticsIdFormatter.canonicalIssueId("fb-abc") == "FB-abc")
        #expect(CrashlyticsIdFormatter.canonicalIssueId("abc") == "FB-abc")
        #expect(CrashIssue(providerId: "abc", exceptionType: "FATAL").id == "FB-abc")
    }

    @Test("event refs accept any case of FB- and match the console session key")
    func eventRefs() throws {
        let ref = try #require(CrashlyticsEventReference("fb-ISSUE/events/ed6f07f2_2272339782204297885"))
        #expect(ref.issueId == "ISSUE")
        let byResourceName = CrashlyticsEvent(eventId: "999", resourceName: "ed6f07f2_2272339782204297885")
        let byEventId = CrashlyticsEvent(eventId: "2272339782204297885", resourceName: "other_1")
        let unrelated = CrashlyticsEvent(eventId: "1", resourceName: "x_1")
        #expect(ref.matches(byResourceName))
        #expect(ref.matches(byEventId))
        #expect(!ref.matches(unrelated))
        #expect(CrashlyticsEventReference("FB-ISSUE") == nil)
        #expect(CrashlyticsEventReference("FB-/events/E") == nil)
    }

    @Test("a console link's platform matches the app id's platform in any case")
    func linkPlatformCase() throws {
        let link = try FirebaseConsoleLink(
            "https://console.firebase.google.com/project/p/crashlytics/app/IOS:com.example.app/issues/abc")
        let config = Config(profiles: ["main": AppProfile(appId: "1:123:ios:abcd", bundleId: "COM.EXAMPLE.APP")])
        #expect(config.appId(for: link) == "1:123:ios:abcd")
        let android = try FirebaseConsoleLink(
            "https://console.firebase.google.com/project/p/crashlytics/app/android:com.example.app/issues/abc")
        #expect(config.appId(for: android) == nil)
    }
}
