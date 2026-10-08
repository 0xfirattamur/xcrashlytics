import Foundation
import Testing
@testable import xcrashlytics

@Suite("RESTCrashlyticsClient resilience")
struct RESTCrashlyticsClientResilienceTests {
    private let appId = "1:623140959935:ios:abcdef0123456789"
    private let okIssues = #"{"groups":[{"issue":{"id":"X","title":"T"}}]}"#

    private func stubResponse(_ status: Int, _ body: String, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        FakeHTTPClient.response(
            URL(string: "https://firebasecrashlytics.googleapis.com")!, status: status, body: Data(body.utf8), headers: headers)
    }

    private func makeClient(
        httpClient: HTTPClient,
        sleeper: Sleeper = SpySleeper(),
        tokens: AccessTokenProvider = StubAccessTokenProvider(),
        dateProvider: DateProvider = FixedDateProvider(),
        jitter: @escaping @Sendable () -> Double = { 1 }
    ) throws -> RESTCrashlyticsClient {
        try RESTCrashlyticsClient(
            httpClient: httpClient, tokens: tokens, sleeper: sleeper, appId: appId, jitter: jitter, dateProvider: dateProvider)
    }

    private func failure(of operation: () async throws -> Void) async -> Error? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Retry math

    @Test("persistent 429: six requests, doubling delays, RATE_LIMITED only after the last")
    func persistentRateLimit() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(429, #"{"error":{"message":"quota"}}"#) }
        let sleeper = SpySleeper()
        let client = try makeClient(httpClient: httpClient, sleeper: sleeper)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .rateLimited(retries: 5))
        #expect(httpClient.requests.count == 6)
        #expect(sleeper.delays == [1, 2, 4, 8, 16])
    }

    @Test("jitter scales each backoff")
    func jitterScalesBackoff() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(429, "") }
        let sleeper = SpySleeper()
        let client = try makeClient(httpClient: httpClient, sleeper: sleeper, jitter: { 0.5 })
        _ = await failure { _ = try await client.fetchIssues() }
        #expect(sleeper.delays == [0.5, 1, 2, 4, 8])
    }

    @Test("429 then success retries and returns the data")
    func rateLimitThenSuccess() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() < 3 ? self.stubResponse(429, "") : self.stubResponse(200, self.okIssues)
        }
        let sleeper = SpySleeper()
        let issues = try await makeClient(httpClient: httpClient, sleeper: sleeper).fetchIssues()
        #expect(issues.map(\.providerId) == ["X"])
        #expect(sleeper.delays == [1, 2])
    }

    @Test("Retry-After seconds is honored, and capped at two minutes")
    func retryAfterSeconds() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            switch counter.next() {
            case 1: return self.stubResponse(429, "", headers: ["Retry-After": "7"])
            case 2: return self.stubResponse(429, "", headers: ["Retry-After": "9999"])
            default: return self.stubResponse(200, self.okIssues)
            }
        }
        let sleeper = SpySleeper()
        _ = try await makeClient(httpClient: httpClient, sleeper: sleeper).fetchIssues()
        #expect(sleeper.delays == [7, 120])
    }

    @Test("Retry-After HTTP date is converted against the dateProvider")
    func retryAfterHTTPDate() async throws {
        let dateProvider = FixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))  // Fri, 15 Jan 2027 08:00:00 GMT
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() == 1
                ? self.stubResponse(503, "", headers: ["Retry-After": "Fri, 15 Jan 2027 08:00:30 GMT"])
                : self.stubResponse(200, self.okIssues)
        }
        let sleeper = SpySleeper()
        _ = try await makeClient(httpClient: httpClient, sleeper: sleeper, dateProvider: dateProvider).fetchIssues()
        #expect(sleeper.delays == [30])
    }

    @Test("retry-after parsing table")
    func retryAfterParsing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RetryPolicy.retryAfterSeconds("3", now: now) == 3)
        #expect(RetryPolicy.retryAfterSeconds(" 1.5 ", now: now) == 1.5)
        #expect(RetryPolicy.retryAfterSeconds("-4", now: now) == 0)
        #expect(RetryPolicy.retryAfterSeconds("Fri, 15 Jan 2027 07:59:00 GMT", now: now) == 0)
        #expect(RetryPolicy.retryAfterSeconds("soon", now: now) == nil)
        #expect(RetryPolicy.retryAfterSeconds(nil, now: now) == nil)
    }

    @Test("503 is retried and, when it persists, reported as an API error — not rate limiting")
    func persistent503() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(503, #"{"error":{"code":503,"message":"The service is unavailable."}}"#) }
        let client = try makeClient(httpClient: httpClient)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .apiError(code: 503, message: "The service is unavailable."))
        #expect(httpClient.requests.count == 6)
    }

    @Test("500, 502, 504 are retried then succeed")
    func serverErrorsRetry() async throws {
        for status in [500, 502, 504] {
            let counter = AtomicCounter()
            let httpClient = FakeHTTPClient { _ in
                counter.next() == 1 ? self.stubResponse(status, "boom") : self.stubResponse(200, self.okIssues)
            }
            let sleeper = SpySleeper()
            _ = try await makeClient(httpClient: httpClient, sleeper: sleeper).fetchIssues()
            #expect(sleeper.delays == [1], "status \(status)")
        }
    }

    @Test("a 400 is not retried and carries Google's message")
    func badRequestNotRetried() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(400, #"{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}"#)
        }
        let sleeper = SpySleeper()
        let client = try makeClient(httpClient: httpClient, sleeper: sleeper)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .apiError(code: 400, message: "Request contains an invalid argument."))
        #expect(httpClient.requests.count == 1)
        #expect(sleeper.delays.isEmpty)
    }

    @Test("a non-JSON error body falls back to its first 200 characters")
    func nonJSONErrorBody() async throws {
        let body = String(repeating: "x", count: 500)
        let httpClient = FakeHTTPClient { _ in self.stubResponse(418, body) }
        let client = try makeClient(httpClient: httpClient)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .apiError(code: 418, message: String(repeating: "x", count: 200)))
    }

    // MARK: - Status mapping

    @Test("a second 401 is unauthorized, after exactly one refresh")
    func secondUnauthorized() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(401, #"{"error":{"message":"Invalid Credentials"}}"#) }
        let tokens = StubAccessTokenProvider(tokens: ["OLD", "FRESH"])
        let client = try makeClient(httpClient: httpClient, tokens: tokens)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(
            error as? CrashlyticsClientError
                == .unauthorized("Google rejected the refreshed access token (401): Invalid Credentials"))
        #expect(httpClient.requests.count == 2)
        #expect(tokens.rejectedTokens == ["OLD"])
    }

    @Test("403 is permissionDenied, never retried")
    func forbidden() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(403, #"{"error":{"message":"The caller does not have permission"}}"#)
        }
        let client = try makeClient(httpClient: httpClient)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(
            error as? CrashlyticsClientError
                == .permissionDenied(
                    "The signed-in Google account cannot read this Crashlytics app (403): The caller does not have permission"))
        #expect(httpClient.requests.count == 1)
    }

    @Test("404 names what was not found")
    func notFound() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(404, #"{"error":{"message":"Requested entity was not found."}}"#) }
        let client = try makeClient(httpClient: httpClient)

        let thrownError = await failure { _ = try await client.fetchIssue(id: "GONE") }
        #expect(thrownError as? CrashlyticsClientError == .notFound("issue GONE was not found in this app; check the issue id."))

        let events = await failure { _ = try await client.fetchEvents(issueId: "GONE", limit: 1, interval: TestWindow.interval) }
        #expect(
            events as? CrashlyticsClientError
                == .notFound("events for issue GONE were not found; the issue or the app does not exist."))

        let report = await failure { _ = try await client.fetchIssues() }
        #expect(
            report as? CrashlyticsClientError
                == .notFound(
                    "Crashlytics app \(appId) was not found in project 623140959935; check the app id in the config."))
    }

    // MARK: - Transport failures

    @Test("transport failures retry briefly, then become a clean network error")
    func transportFailure() async throws {
        let offline = "The Internet connection appears to be offline."
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.transport(offline) }
        let sleeper = SpySleeper()
        let client = try makeClient(httpClient: httpClient, sleeper: sleeper)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .network(offline))
        #expect(httpClient.requests.count == 3)
        #expect(sleeper.delays == [1, 2])
    }

    @Test("a transient transport failure recovers")
    func transportRecovers() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            if counter.next() == 1 { throw HTTPTransportError.transport("The request timed out.") }
            return self.stubResponse(200, self.okIssues)
        }
        let issues = try await makeClient(httpClient: httpClient).fetchIssues()
        #expect(issues.count == 1)
    }

    @Test("a cancelled transport call is CancellationError and is not retried")
    func cancelledTransport() async throws {
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.cancelled }
        let client = try makeClient(httpClient: httpClient)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error is CancellationError)
        #expect(httpClient.requests.count == 1)
    }

    @Test("cancellation during backoff stops the retry loop")
    func cancellationDuringBackoff() async throws {
        struct CancellingSleeper: Sleeper {
            func sleep(seconds: Double) async throws { throw CancellationError() }
        }
        let httpClient = FakeHTTPClient { _ in self.stubResponse(429, "") }
        let client = try makeClient(httpClient: httpClient, sleeper: CancellingSleeper())
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error is CancellationError)
        #expect(httpClient.requests.count == 1)
    }

    @Test("a token provider network failure is not retried by the client")
    func tokenNetworkFailure() async throws {
        struct OfflineTokens: AccessTokenProvider {
            func token() async throws -> String { throw CrashlyticsClientError.network("offline") }
            func forceRefresh(rejecting token: String) async throws -> String { throw CrashlyticsClientError.network("offline") }
        }
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, self.okIssues) }
        let client = try makeClient(httpClient: httpClient, tokens: OfflineTokens())
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .network("offline"))
        #expect(httpClient.requests.isEmpty)
    }

    // MARK: - Query and paging

    @Test("fetchIssues sends the interval explicitly, with query parameters in sorted order")
    func intervalQuery() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"groups":[]}"#) }
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
        _ = try await makeClient(httpClient: httpClient).fetchIssues(limit: 25, interval: interval)
        let url = try #require(httpClient.requests.first?.url)
        #expect(url.path == "/v1alpha/projects/623140959935/apps/\(appId)/reports/topIssues")
        #expect(
            url.query
                == "filter.interval.endTime=1970-01-02T00:00:00Z&filter.interval.startTime=1970-01-01T00:00:00Z&page_size=25")
    }

    @Test("without an interval no filter is sent (the API's 7-day default)")
    func noIntervalQuery() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"groups":[]}"#) }
        _ = try await makeClient(httpClient: httpClient).fetchIssues(limit: nil, interval: nil)
        #expect(httpClient.requests.first?.url?.query == "page_size=100")
    }

    @Test("page tokens are encoded strictly so + & = survive")
    func pageTokenEncoding() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() == 1
                ? self.stubResponse(200, #"{"groups":[{"issue":{"id":"A"}}],"nextPageToken":"a+b&c=d"}"#)
                : self.stubResponse(200, #"{"groups":[]}"#)
        }
        _ = try await makeClient(httpClient: httpClient).fetchIssues()
        let second = try #require(httpClient.requests.last?.url)
        #expect(second.query == "page_size=100&page_token=a%2Bb%26c%3Dd")
        #expect(URLComponents(url: second, resolvingAgainstBaseURL: false)?.queryItems?.last?.value == "a%2Bb%26c%3Dd".removingPercentEncoding)
    }

    @Test("an empty nextPageToken ends paging")
    func emptyTokenEnds() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"groups":[{"issue":{"id":"A"}}],"nextPageToken":""}"#) }
        let issues = try await makeClient(httpClient: httpClient).fetchIssues()
        #expect(issues.count == 1)
        #expect(httpClient.requests.count == 1)
    }

    @Test("a repeated page token ends paging")
    func repeatedTokenEnds() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"events":[{"eventId":"E"}],"nextPageToken":"SAME"}"#) }
        let events = try await makeClient(httpClient: httpClient).fetchEvents(issueId: "I1", limit: nil, interval: TestWindow.interval)
        #expect(events.count == 2)
        #expect(httpClient.requests.count == 2)
    }

    @Test("paging stops at the page cap")
    func pageCap() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"{"groups":[{"issue":{"id":"A"}}],"nextPageToken":"T\#(counter.next())"}"#)
        }
        let issues = try await makeClient(httpClient: httpClient).fetchIssues()
        #expect(httpClient.requests.count == RESTCrashlyticsClient.maxPages)
        #expect(issues.count == RESTCrashlyticsClient.maxPages)
    }

    @Test("fetchEvents pages with page_token until limit is reached")
    func eventsPaging() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            let n = counter.next()
            return self.stubResponse(200, #"{"events":[{"eventId":"E\#(n)a"},{"eventId":"E\#(n)b"}],"nextPageToken":"P\#(n)"}"#)
        }
        let events = try await makeClient(httpClient: httpClient).fetchEvents(
            issueId: "I1", pageSize: 2, limit: 5, interval: TestWindow.interval)
        #expect(events.map(\.eventId) == ["E1a", "E1b", "E2a", "E2b", "E3a"])
        #expect(httpClient.requests.allSatisfy { $0.url?.path.hasSuffix("/events") == true })
        let queries = httpClient.requests.compactMap { $0.url?.query }
        let window = "filter.interval.endTime=\(TestWindow.endQuery)&filter.interval.startTime=\(TestWindow.startQuery)"
        #expect(queries == [
            "\(window)&filter.issue.id=I1&page_size=2",
            "\(window)&filter.issue.id=I1&page_size=2&page_token=P1",
            "\(window)&filter.issue.id=I1&page_size=2&page_token=P2"
        ])
    }

    // MARK: - Lossy decoding

    @Test("topIssues skips an issue without an id and reads numeric counts")
    func lossyIssues() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
            {"groups":[
              {"issue":{"title":"no id"},"metrics":[{"eventsCount":5}]},
              {"issue":{"id":"I2","state":"MUTED"},"metrics":[{"eventsCount":123,"impactedUsersCount":"7"}]},
              "garbage",
              {"issue":{"id":"I3"},"metrics":[{"eventsCount":"abc"}]}
            ]}
            """#)
        }
        let issues = try await makeClient(httpClient: httpClient).fetchIssues()
        #expect(issues.map(\.providerId) == ["I2", "I3"])
        #expect(issues[0].eventsCount == 123)
        #expect(issues[0].impactedUsersCount == 7)
        #expect(issues[0].state == "MUTED")
        #expect(issues[1].eventsCount == nil)
    }

    @Test("an event with a numeric line and a broken sibling event still decode")
    func lossyEvents() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
            {"events":[
              {"eventId":"E1","threads":[{"crashed":true,"frames":[
                {"symbol":"a","line":42,"column":"7","address":"4295000000","offset":12},
                {"symbol":{"not":"a string"}},
                {"symbol":"b","line":"9"}
              ]}]},
              "not an event",
              {"eventId":"E3","threads":"oops"}
            ]}
            """#)
        }
        let events = try await makeClient(httpClient: httpClient).fetchEvents(issueId: "I1", limit: nil, interval: TestWindow.interval)
        #expect(events.map(\.eventId) == ["E1", "E3"])
        let frames = events[0].threads[0].frames
        #expect(frames.map(\.symbol) == ["a", "b"])
        #expect(frames[0].line == 42)
        #expect(frames[0].column == 7)
        #expect(frames[0].address == 4_295_000_000)
        #expect(frames[0].offset == "12")
        #expect(frames[1].line == 9)
        #expect(events[1].threads.isEmpty)
        #expect(events[0].rawJSON?.contains(#""eventId":"E1""#) == true)
    }

    @Test("a body that is not JSON is a readable decoding error")
    func undecodableBody() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, "<html>captive portal</html>") }
        let client = try makeClient(httpClient: httpClient)
        let error = await failure { _ = try await client.fetchIssues() }
        #expect(error as? CrashlyticsClientError == .decodingFailed("top issues report: the body is not valid JSON"))

        let thrownError = await failure { _ = try await client.fetchIssue(id: "I1") }
        #expect(thrownError as? CrashlyticsClientError == .decodingFailed("issue I1: the body is not valid JSON"))

        let events = await failure { _ = try await client.fetchEvents(issueId: "I1", limit: 1, interval: TestWindow.interval) }
        #expect(events as? CrashlyticsClientError == .decodingFailed("events of issue I1: the body is not the expected JSON object"))
    }

    @Test("an issue detail without an id names the missing field")
    func detailMissingID() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(200, #"{"title":"x"}"#) }
        let error = await failure { _ = try await self.makeClient(httpClient: httpClient).fetchIssue(id: "I1") }
        #expect(error as? CrashlyticsClientError == .decodingFailed("issue I1: missing field 'id' at the body"))
    }

    // MARK: - Impact

    @Test("issueImpact reads counts and app users from the windowed report")
    func impact() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(200, #"""
            {"groups":[
              {"issue":{"id":"OTHER"},"metrics":[{"eventsCount":"9","impactedUsersCount":"3","totalUsersCount":"1000"}]},
              {"issue":{"id":"I1"},"metrics":[{"eventsCount":40,"impactedUsersCount":"10","totalUsersCount":"1000"}]}
            ]}
            """#)
        }
        let since = Date(timeIntervalSince1970: 0)
        let until = Date(timeIntervalSince1970: 86_400)
        let impact = try await makeClient(httpClient: httpClient).fetchIssueImpact(issueId: "I1", since: since, until: until, maxPages: 3)
        #expect(impact == IssueImpact(since: since, until: until, eventsCount: 40, impactedUsersCount: 10, appUsersCount: 1000))
    }
}
