import Foundation
import Testing
@testable import xcrashlytics

@Suite("RESTCrashlyticsClient")
struct RESTCrashlyticsClientTests {
    private let appId = "1:623140959935:ios:abcdef0123456789"
    private let projectNumber = "623140959935"

    private func stubResponse(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        let r = HTTPURLResponse(
            url: URL(string: "https://firebasecrashlytics.googleapis.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), r)
    }

    private func makeClient(httpClient: HTTPClient, sleeper: Sleeper = SpySleeper()) throws -> RESTCrashlyticsClient {
        try RESTCrashlyticsClient(
            httpClient: httpClient,
            tokens: StubAccessTokenProvider(),
            sleeper: sleeper,
            appId: appId
        )
    }

    @Test("FirebaseAppId.projectNumber extracts numeric segment")
    func projectNumberExtraction() {
        #expect(FirebaseAppId.projectNumber(from: appId) == projectNumber)
        #expect(FirebaseAppId.projectNumber(from: "bogus") == nil)
    }

    @Test("init rejects badly-shaped appId")
    func badAppId() {
        let httpClient = FakeHTTPClient()
        #expect(throws: ConfigError.invalidAppId("not-an-app-id")) {
            _ = try RESTCrashlyticsClient(
                httpClient: httpClient,
                tokens: StubAccessTokenProvider(),
                sleeper: SpySleeper(),
                appId: "not-an-app-id"
            )
        }
    }

    @Test("fetchIssues pages through topIssues groups")
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
        let httpClient = FakeHTTPClient { _ in
            counter.n += 1
            return counter.n == 1 ? self.stubResponse(200, page1) : self.stubResponse(200, page2)
        }
        let client = try makeClient(httpClient: httpClient)
        let events = try await client.fetchIssues()
        #expect(events.map { $0.id } == ["FB-I1", "FB-I2", "FB-I3"])
        #expect(events.map { $0.providerId } == ["I1", "I2", "I3"])
        #expect(events.allSatisfy { $0.source == .firebase })
        #expect(counter.n == 2)
    }

    @Test("limit stops paging early and trims to the cap")
    func limitStopsPaging() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let httpClient = FakeHTTPClient { _ in
            counter.n += 1
            return self.stubResponse(200, #"""
            {"groups":[
              {"issue":{"id":"I1","title":"A"}},
              {"issue":{"id":"I2","title":"B"}}
            ],"nextPageToken":"NEXT"}
            """#)
        }
        let client = try makeClient(httpClient: httpClient)
        let events = try await client.fetchIssues(limit: 1)
        #expect(events.map { $0.id } == ["FB-I1"])
        #expect(counter.n == 1) // never fetched the second page
    }

    @Test("401 refreshes the rejected token once and retries with the new one")
    func refreshOn401() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            if counter.next() == 1 { return self.stubResponse(401, #"{"error":{"message":"expired"}}"#) }
            return self.stubResponse(200, #"{"groups":[{"issue":{"id":"X","title":"T"}}]}"#)
        }
        let tokens = StubAccessTokenProvider(tokens: ["OLD", "FRESH"])
        let client = try RESTCrashlyticsClient(
            httpClient: httpClient, tokens: tokens, sleeper: SpySleeper(),
            appId: appId
        )
        _ = try await client.fetchIssues()
        #expect(tokens.rejectedTokens == ["OLD"])
        #expect(httpClient.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer OLD", "Bearer FRESH"])
    }

    @Test("fetchIssue decodes into CrashIssue")
    func detailDecode() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
            {"id":"DETAIL","title":"NSInvalidArgument","errorType":"FATAL","subtitle":"oh no","state":"OPEN"}
            """#)
        }
        let client = try makeClient(httpClient: httpClient)
        let event = try await client.fetchIssue(id: "DETAIL")
        #expect(event.exception.exceptionType == "FATAL")
        #expect(event.exception.subtype == "oh no")
        #expect(event.source == .firebase)
        #expect(event.errorType == "FATAL")
        #expect(event.state == "OPEN")
    }

    @Test("fetchEvents decodes runtime details")
    func fetchEventsRuntimeDetails() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
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
        let client = try makeClient(httpClient: httpClient)

        let events = try await client.fetchEvents(issueId: "I1", limit: 5, interval: TestWindow.interval)

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
        #expect(FrameSelector().frames(from: events[0]).first?.symbol == "BlurDetectionService.classifyWithML(_:)")
        #expect(events[0].rawJSON?.contains(#""unknownRuntime":"keep""#) == true)
    }

    @Test("fetchEvents accepts object-shaped issue references")
    func fetchEventsObjectIssueReference() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
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
        let client = try makeClient(httpClient: httpClient)

        let events = try await client.fetchEvents(issueId: "3aedb610eee1a41872d991ca62ce8566", limit: 1, interval: TestWindow.interval)

        #expect(events.count == 1)
        #expect(events[0].issueId == "3aedb610eee1a41872d991ca62ce8566")
        #expect(FrameSelector().frames(from: events[0]).first?.symbol == "BlurDetectionService.classifyWithML(_:)")
    }

    @Test("malformed issue id throws invalidRequest instead of crashing")
    func malformedIssueIdThrows() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"events":[]}"#) }
        let client = try makeClient(httpClient: httpClient)
        await #expect(throws: CrashlyticsClientError.invalidRequest("issue id '../etc/passwd' contains unsupported characters.")) {
            _ = try await client.fetchIssue(id: "../etc/passwd")
        }
    }

    @Test("issue id with spaces throws invalidRequest from fetchEvents")
    func spaceIssueIdThrows() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"events":[]}"#) }
        let client = try makeClient(httpClient: httpClient)
        await #expect(throws: CrashlyticsClientError.invalidRequest("issue id 'a b' contains unsupported characters.")) {
            _ = try await client.fetchEvents(issueId: "a b", limit: 1, interval: TestWindow.interval)
        }
    }

    // MARK: - App id validation

    @Test("init rejects appId with path traversal characters")
    func appIdWithPathTraversalRejected() {
        let httpClient = FakeHTTPClient()
        #expect(throws: ConfigError.invalidAppId("1:123456:android:abc/../evil")) {
            _ = try RESTCrashlyticsClient(
                httpClient: httpClient,
                tokens: StubAccessTokenProvider(),
                sleeper: SpySleeper(),
                appId: "1:123456:android:abc/../evil"
            )
        }
    }

    @Test("init rejects appId containing percent-encoded traversal")
    func appIdWithPercentEncodingRejected() {
        let httpClient = FakeHTTPClient()
        #expect(throws: ConfigError.invalidAppId("1:123456:android:abc%2F..%2Fevil")) {
            _ = try RESTCrashlyticsClient(
                httpClient: httpClient,
                tokens: StubAccessTokenProvider(),
                sleeper: SpySleeper(),
                appId: "1:123456:android:abc%2F..%2Fevil"
            )
        }
    }

    // MARK: - Issue id validation

    @Test("empty issue id throws 'must not be empty' from fetchIssue")
    func emptyIssueIdThrowsEmptyError() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"events":[]}"#) }
        let client = try makeClient(httpClient: httpClient)
        await #expect(throws: CrashlyticsClientError.invalidRequest("issue id must not be empty.")) {
            _ = try await client.fetchIssue(id: "")
        }
    }

    @Test("empty issue id throws 'must not be empty' from fetchEvents")
    func emptyIssueIdThrowsFromFetchEvents() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"events":[]}"#) }
        let client = try makeClient(httpClient: httpClient)
        await #expect(throws: CrashlyticsClientError.invalidRequest("issue id must not be empty.")) {
            _ = try await client.fetchEvents(issueId: "", limit: 1, interval: TestWindow.interval)
        }
    }

}
