import Foundation
import Testing
@testable import xcrashlytics

@Suite("RESTCrashlyticsClient reports")
struct RESTCrashlyticsClientReportTests {
    private let appId = "1:623140959935:ios:abcdef0123456789"

    private func stubResponse(_ body: String) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://firebasecrashlytics.googleapis.com")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    private func makeClient(_ httpClient: HTTPClient) throws -> RESTCrashlyticsClient {
        try RESTCrashlyticsClient(httpClient: httpClient, tokens: StubAccessTokenProvider(), sleeper: SpySleeper(), appId: appId)
    }

    private func items(_ request: URLRequest?) throws -> [URLQueryItem] {
        let url = try #require(request?.url)
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    private let dailyIssues = #"""
    {"groups":[{"issue":{"id":"I1"},"metrics":[
      {"eventsCount":"9","impactedUsersCount":"4","startTime":"2026-10-01T09:00:00Z","endTime":"2026-10-04T09:00:00Z"},
      {"eventsCount":"2","startTime":"2026-10-01T09:00:00Z","endTime":"2026-10-02T00:00:00Z"},
      {"eventsCount":"0","startTime":"2026-10-02T00:00:00Z","endTime":"2026-10-03T00:00:00Z"},
      {"eventsCount":"4","startTime":"2026-10-03T00:00:00Z","endTime":"2026-10-04T00:00:00Z"},
      {"eventsCount":"4","startTime":"2026-10-03T00:00:00Z","endTime":"2026-10-04T00:00:00Z"},
      {"eventsCount":"3","startTime":"2026-10-04T00:00:00Z","endTime":"2026-10-04T09:00:00Z"}]}]}
    """#

    @Test("daily listings send TIME_GRANULARITY_DAY and read the series after the total point")
    func dailySeries() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(self.dailyIssues) }
        let issues = try await makeClient(httpClient).fetchIssues(
            limit: 10, interval: TestWindow.interval, options: IssueQueryOptions(includesDailyCounts: true))

        let request = httpClient.requests.first
        #expect(try items(request).first { $0.name == "granularity" }?.value == "TIME_GRANULARITY_DAY")
        let issue = try #require(issues.first)
        #expect(issue.eventsCount == 9)
        #expect(issue.impactedUsersCount == 4)
        // The total (9) is not a day; the zero day is dropped; the repeated 10-03 point counts once.
        #expect(issue.dailyEvents == [
            DailyEventCount(day: "2026-10-01", eventsCount: 2),
            DailyEventCount(day: "2026-10-03", eventsCount: 4),
            DailyEventCount(day: "2026-10-04", eventsCount: 3)
        ])
        #expect(issue.dailyEvents?.reduce(0) { $0 + $1.eventsCount } == issue.eventsCount)
    }

    @Test("without the daily option no granularity is requested and no series is built")
    func noDailyByDefault() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(self.dailyIssues) }
        let issues = try await makeClient(httpClient).fetchIssues(limit: 10, interval: TestWindow.interval)
        #expect(try items(httpClient.requests.first).contains { $0.name == "granularity" } == false)
        #expect(issues.first?.dailyEvents == nil)
        #expect(issues.first?.eventsCount == 9)
    }

    @Test("version display names are sent as repeated filter.version.displayNames items")
    func repeatedDisplayNames() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(#"{"groups":[]}"#) }
        _ = try await makeClient(httpClient).fetchIssues(
            limit: 10, interval: TestWindow.interval,
            options: IssueQueryOptions(versionDisplayNames: ["6.23.0 (1112)", "6.22.0 (1090)"]))

        let names = try items(httpClient.requests.first).filter { $0.name == "filter.version.displayNames" }.compactMap(\.value)
        #expect(names == ["6.22.0 (1090)", "6.23.0 (1112)"])
        let query = try #require(httpClient.requests.first?.url?.query)
        #expect(query.contains(
            "filter.version.displayNames=6.22.0%20%281090%29&filter.version.displayNames=6.23.0%20%281112%29"))
    }

    @Test("fetchReportedVersions pages topVersions over the interval and reads the version names")
    func fetchReportedVersionsPages() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() == 1
                ? self.stubResponse(#"""
                {"groups":[{"version":{"displayVersion":"6.23.0","buildVersion":"1112","displayName":"6.23.0 (1112)"}}],
                 "nextPageToken":"P2"}
                """#)
                : self.stubResponse(#"""
                {"groups":[{"version":{"displayVersion":"6.22.0","buildVersion":"1090","displayName":"6.22.0 (1090)"}},
                           {"version":{}},{"metrics":[]}]}
                """#)
        }
        let versions = try await makeClient(httpClient).fetchReportedVersions(interval: TestWindow.interval)

        #expect(versions.map(\.displayName) == ["6.23.0 (1112)", "6.22.0 (1090)"])
        #expect(versions.map(\.displayVersion) == ["6.23.0", "6.22.0"])
        #expect(versions.map(\.buildVersion) == ["1112", "1090"])
        #expect(httpClient.requests.count == 2)
        #expect(httpClient.requests.first?.url?.path == "/v1alpha/projects/623140959935/apps/\(appId)/reports/topVersions")
        #expect(try items(httpClient.requests.last).first { $0.name == "page_token" }?.value == "P2")
        #expect(try items(httpClient.requests.first).first { $0.name == "filter.interval.startTime" }?.value == TestWindow.startQuery)
    }

    @Test("a version without a display name gets \"display (build)\"")
    func versionNameFallback() throws {
        let versionDTO = CrashlyticsDTO.Version(displayVersion: "6.1.0", buildVersion: "7", displayName: nil)
        #expect(CrashlyticsReportMapper().reportedVersion(from: versionDTO)?.displayName == "6.1.0 (7)")
    }

    @Test("dailyEvents sums each version's daily series, filtered to the issue")
    func issueDailyEvents() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(#"""
            {"groups":[
              {"version":{"displayVersion":"6.2.0","buildVersion":"2","displayName":"6.2.0 (2)"},"metrics":[
                {"eventsCount":"8","startTime":"2026-10-01T00:00:00Z","endTime":"2026-10-03T00:00:00Z"},
                {"eventsCount":"5","startTime":"2026-10-01T00:00:00Z","endTime":"2026-10-02T00:00:00Z"},
                {"eventsCount":"3","startTime":"2026-10-02T00:00:00Z","endTime":"2026-10-03T00:00:00Z"}]},
              {"version":{"displayVersion":"6.1.0","buildVersion":"1","displayName":"6.1.0 (1)"},"metrics":[
                {"eventsCount":"4","startTime":"2026-10-01T00:00:00Z","endTime":"2026-10-03T00:00:00Z"},
                {"eventsCount":"4","startTime":"2026-10-02T00:00:00Z","endTime":"2026-10-03T00:00:00Z"}]}
            ]}
            """#)
        }
        let days = try await makeClient(httpClient).fetchDailyEventCounts(issueId: "I1", interval: TestWindow.interval)

        #expect(days == [DailyEventCount(day: "2026-10-01", eventsCount: 5), DailyEventCount(day: "2026-10-02", eventsCount: 7)])
        let request = try items(httpClient.requests.first)
        #expect(request.first { $0.name == "filter.issue.id" }?.value == "I1")
        #expect(request.first { $0.name == "granularity" }?.value == "TIME_GRANULARITY_DAY")
        #expect(httpClient.requests.first?.url?.path.hasSuffix("/reports/topVersions") == true)
    }
}
