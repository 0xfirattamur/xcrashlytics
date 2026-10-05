import Foundation
import Testing
@testable import xcrashlytics

@Suite("CrashlyticsClient")
struct CrashlyticsClientTests {
    private let appId = "1:623140959935:ios:abcdef0123456789"
    private let projectNumber = "623140959935"

    private func resp(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        let r = HTTPURLResponse(
            url: URL(string: "https://firebasecrashlytics.googleapis.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), r)
    }

    private func makeClient(http: HTTPTransport, sleeper: Sleeper = MockSleeper()) throws -> CrashlyticsClient {
        try CrashlyticsClient(
            httpTransport: http,
            tokens: MockTokenProvider(),
            sleeper: sleeper,
            appId: appId
        )
    }

    @Test("projectNumber(fromAppId:) extracts numeric segment")
    func projectNumberExtraction() {
        #expect(CrashlyticsClient.projectNumber(fromAppId: appId) == projectNumber)
        #expect(CrashlyticsClient.projectNumber(fromAppId: "bogus") == nil)
    }

    @Test("init rejects badly-shaped appId")
    func badAppId() {
        let http = MockHTTPTransport()
        #expect(throws: FirebaseError.self) {
            _ = try CrashlyticsClient(
                httpTransport: http,
                tokens: MockTokenProvider(),
                sleeper: MockSleeper(),
                appId: "not-an-app-id"
            )
        }
    }

    @Test("listIssues pages through topIssues groups")
    func pagingTopIssues() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let page1 = #"""
        {"groups":[
          {"issue":{"id":"I1","title":"A","errorType":"FATAL"},"metrics":[{"eventsCount":"100","impactedUsersCount":"42"}]},
          {"issue":{"id":"I2","title":"B","errorType":"FATAL"}}
        ],"nextPageToken":"NEXT"}
        """#
        let page2 = #"""
        {"groups":[{"issue":{"id":"I3","title":"C","errorType":"NON_FATAL"}}]}
        """#
        let http = MockHTTPTransport { _ in
            counter.n += 1
            return counter.n == 1 ? self.resp(200, page1) : self.resp(200, page2)
        }
        let client = try makeClient(http: http)
        let events = try await client.listIssues()
        #expect(events.map { $0.id } == ["FB-I1", "FB-I2", "FB-I3"])
        #expect(events.map { $0.providerId } == ["I1", "I2", "I3"])
        #expect(events.allSatisfy { $0.source == .firebase })
        #expect(counter.n == 2)
    }

    @Test("maxIssues stops paging early and trims to the cap")
    func maxIssuesStopsPaging() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let http = MockHTTPTransport { _ in
            counter.n += 1
            return self.resp(200, #"""
            {"groups":[
              {"issue":{"id":"I1","title":"A"}},
              {"issue":{"id":"I2","title":"B"}}
            ],"nextPageToken":"NEXT"}
            """#)
        }
        let client = try makeClient(http: http)
        let events = try await client.listIssues(maxIssues: 1)
        #expect(events.map { $0.id } == ["FB-I1"])
        #expect(counter.n == 1) // never fetched the second page
    }

    @Test("429 backs off via Sleeper then succeeds")
    func rateLimitRetries() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let http = MockHTTPTransport { _ in
            counter.n += 1
            if counter.n < 3 { return self.resp(429, #"{"error":"rate"}"#) }
            return self.resp(200, #"{"groups":[{"issue":{"id":"X","title":"T"}}]}"#)
        }
        let sleeper = MockSleeper()
        let client = try makeClient(http: http, sleeper: sleeper)
        _ = try await client.listIssues()
        #expect(sleeper.delays.count == 2)
    }

    @Test("401 triggers forceRefresh and retries once")
    func refreshOn401() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let http = MockHTTPTransport { _ in
            counter.n += 1
            if counter.n == 1 { return self.resp(401, #"{"error":"expired"}"#) }
            return self.resp(200, #"{"groups":[{"issue":{"id":"X","title":"T"}}]}"#)
        }
        let tokens = MockTokenProvider(tokens: ["OLD", "FRESH"])
        let client = try CrashlyticsClient(
            httpTransport: http, tokens: tokens, sleeper: MockSleeper(),
            appId: appId
        )
        _ = try await client.listIssues()
        #expect(tokens.forceRefreshCalls == 1)
    }

    @Test("getIssueDetail decodes into CrashIssue")
    func detailDecode() async throws {
        let http = MockHTTPTransport { _ in
            self.resp(200, #"""
            {"id":"DETAIL","title":"NSInvalidArgument","errorType":"FATAL","subtitle":"oh no","state":"OPEN"}
            """#)
        }
        let client = try makeClient(http: http)
        let event = try await client.getIssueDetail(id: "DETAIL")
        #expect(event.exception.exceptionType == "FATAL")
        #expect(event.exception.subtype == "oh no")
        #expect(event.source == .firebase)
    }

    @Test("representativeFrames pulls the crashed thread's frames from the sample event")
    func representativeFramesFromEvent() async throws {
        let http = MockHTTPTransport { _ in
            self.resp(200, #"""
            {"events":[{"threads":[{"crashed":true,"frames":[
              {"symbol":"-[VC crash]","library":"MyApp"},
              {"symbol":"main","library":"MyApp"}
            ]}]}]}
            """#)
        }
        let client = try makeClient(http: http)
        let frames = try await client.representativeFrames(issueID: "I1")
        #expect(frames.count == 2)
        #expect(frames.first?.symbol == "-[VC crash]")
        #expect(frames.first?.binaryName == "MyApp")
        let req = http.requests.last!
        #expect(req.url?.path.hasSuffix("/events") == true)
        #expect(req.url?.query?.contains("filter.issue.id=I1") == true)
    }

    @Test("representativeFrames falls back to the first thread when crashed flag is absent")
    func representativeFramesFromFirstThread() async throws {
        let http = MockHTTPTransport { _ in
            self.resp(200, #"""
            {"events":[{"threads":[{"frames":[
              {"symbol":"FIRCLSUserLoggingRecordError","library":"Core"},
              {"symbol":"BlurDetectionService.classifyWithML(_)","library":"Core"}
            ]}]}]}
            """#)
        }
        let client = try makeClient(http: http)
        let frames = try await client.representativeFrames(issueID: "I1")
        #expect(frames.count == 2)
        #expect(frames.first?.symbol == "FIRCLSUserLoggingRecordError")
    }

    @Test("listEvents decodes runtime details")
    func listEventsRuntimeDetails() async throws {
        let http = MockHTTPTransport { _ in
            self.resp(200, #"""
            {"events":[{
              "name":"projects/123/apps/app/events/E1",
              "eventId":"E1",
              "eventTime":"2026-06-05T12:09:45Z",
              "processState":"FOREGROUND",
              "version":{"displayVersion":"6.16.0","buildVersion":"937"},
              "device":{"model":"iPhone 17 Pro Max","orientation":"PORTRAIT"},
              "operatingSystem":{"displayVersion":"26.4.1","jailbroken":false,"orientation":"PORTRAIT"},
              "memory":{"free":"675335168","used":"1234567890"},
              "storage":{"free":"12345","used":"67890"},
              "user":{"id":"033EF509-4BDD-4596-8BA9-E988E3342614"},
              "unknownRuntime":"keep",
              "blameFrame":{"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true},
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]
            }]}
            """#)
        }
        let client = try makeClient(http: http)

        let events = try await client.listEvents(issueID: "I1", maxEvents: 5)

        #expect(events.count == 1)
        #expect(events[0].eventId == "E1")
        #expect(events[0].displayVersion == "6.16.0")
        #expect(events[0].buildVersion == "937")
        #expect(events[0].deviceModel == "iPhone 17 Pro Max")
        #expect(events[0].deviceOrientation == "PORTRAIT")
        #expect(events[0].osVersion == "26.4.1")
        #expect(events[0].jailbroken == false)
        #expect(events[0].memoryFree == 675_335_168)
        #expect(events[0].storageUsed == 67_890)
        #expect(events[0].userId == "033EF509-4BDD-4596-8BA9-E988E3342614")
        #expect(events[0].representativeFrames().first?.symbol == "BlurDetectionService.classifyWithML(_:)")
        #expect(events[0].rawJSON?.contains(#""unknownRuntime":"keep""#) == true)
    }

    @Test("listEvents accepts object-shaped issue references")
    func listEventsObjectIssueReference() async throws {
        let http = MockHTTPTransport { _ in
            self.resp(200, #"""
            {"events":[{
              "eventId":"E1",
              "issue":{
                "name":"projects/123/apps/app/issues/3aedb610eee1a41872d991ca62ce8566",
                "id":"3aedb610eee1a41872d991ca62ce8566",
                "title":"Blur crash"
              },
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core"}
              ]}]
            }]}
            """#)
        }
        let client = try makeClient(http: http)

        let events = try await client.listEvents(issueID: "3aedb610eee1a41872d991ca62ce8566", maxEvents: 1)

        #expect(events.count == 1)
        #expect(events[0].issueId == "3aedb610eee1a41872d991ca62ce8566")
        #expect(events[0].representativeFrames().first?.symbol == "BlurDetectionService.classifyWithML(_:)")
    }

    @Test("representativeFrames returns empty when the issue has no events")
    func representativeFramesEmpty() async throws {
        let http = MockHTTPTransport { _ in self.resp(200, #"{"events":[]}"#) }
        let client = try makeClient(http: http)
        let frames = try await client.representativeFrames(issueID: "I1")
        #expect(frames.isEmpty)
    }

    @Test("malformed issue id throws invalidRequest instead of crashing")
    func malformedIssueIdThrows() async throws {
        let http = MockHTTPTransport { _ in self.resp(200, #"{"events":[]}"#) }
        let client = try makeClient(http: http)
        await #expect(throws: FirebaseError.invalidRequest("issue id '../etc/passwd' contains unsupported characters.")) {
            _ = try await client.getIssueDetail(id: "../etc/passwd")
        }
    }

    @Test("issue id with spaces throws invalidRequest from listEvents")
    func spaceIssueIdThrows() async throws {
        let http = MockHTTPTransport { _ in self.resp(200, #"{"events":[]}"#) }
        let client = try makeClient(http: http)
        await #expect(throws: FirebaseError.invalidRequest("issue id 'a b' contains unsupported characters.")) {
            _ = try await client.listEvents(issueID: "a b", maxEvents: 1)
        }
    }

    // MARK: - App id validation

    @Test("init rejects appId with path traversal characters")
    func appIdWithPathTraversalRejected() {
        let http = MockHTTPTransport()
        #expect(throws: FirebaseError.self) {
            _ = try CrashlyticsClient(
                httpTransport: http,
                tokens: MockTokenProvider(),
                sleeper: MockSleeper(),
                appId: "1:123456:android:abc/../evil"
            )
        }
    }

    @Test("init rejects appId containing percent-encoded traversal")
    func appIdWithPercentEncodingRejected() {
        let http = MockHTTPTransport()
        #expect(throws: FirebaseError.self) {
            _ = try CrashlyticsClient(
                httpTransport: http,
                tokens: MockTokenProvider(),
                sleeper: MockSleeper(),
                appId: "1:123456:android:abc%2F..%2Fevil"
            )
        }
    }

    @Test("init accepts well-formed appId with allowed characters")
    func appIdWellFormedAccepted() {
        let http = MockHTTPTransport()
        #expect(throws: Never.self) {
            _ = try CrashlyticsClient(
                httpTransport: http,
                tokens: MockTokenProvider(),
                sleeper: MockSleeper(),
                appId: "1:623140959935:ios:abcdef0123456789"
            )
        }
    }

    // MARK: - Issue id validation

    @Test("empty issue id throws 'must not be empty' from getIssueDetail")
    func emptyIssueIdThrowsEmptyError() async throws {
        let http = MockHTTPTransport { _ in self.resp(200, #"{"events":[]}"#) }
        let client = try makeClient(http: http)
        await #expect(throws: FirebaseError.invalidRequest("issue id must not be empty.")) {
            _ = try await client.getIssueDetail(id: "")
        }
    }

    @Test("empty issue id throws 'must not be empty' from listEvents")
    func emptyIssueIdThrowsFromListEvents() async throws {
        let http = MockHTTPTransport { _ in self.resp(200, #"{"events":[]}"#) }
        let client = try makeClient(http: http)
        await #expect(throws: FirebaseError.invalidRequest("issue id must not be empty.")) {
            _ = try await client.listEvents(issueID: "", maxEvents: 1)
        }
    }

}
