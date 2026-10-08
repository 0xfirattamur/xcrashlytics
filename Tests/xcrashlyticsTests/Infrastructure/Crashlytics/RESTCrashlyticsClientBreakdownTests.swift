import Foundation
import Testing
@testable import xcrashlytics

@Suite("RESTCrashlyticsClient breakdown")
struct RESTCrashlyticsClientBreakdownTests {
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

    private func version(_ display: String, _ build: String, events: Int, users: Int, total: Int, crashFree: Double? = nil) -> String {
        let free = crashFree.map { #","crashFreeUsersPercentage":\#($0)"# } ?? ""
        return #"""
        {"version":{"displayVersion":"\#(display)","buildVersion":"\#(build)","displayName":"\#(display) (\#(build))"},
         "metrics":[{"eventsCount":"\#(events)","impactedUsersCount":"\#(users)","sessionsCount":"\#(events)",
                     "totalUsersCount":"\#(total)","totalSessionsCount":"\#(total * 10)"\#(free)}]}
        """#
    }

    @Test("versions: pages are merged, zero-event groups dropped, rows sorted by events, shares and user percentages computed")
    func versionsForIssue() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() == 1
                ? self.stubResponse(#"{"groups":[\#(self.version("4.0.0", "101", events: 30, users: 3, total: 300)),"#
                    + self.version("3.9.0", "90", events: 0, users: 0, total: 1000) + #"],"nextPageToken":"P2"}"#)
                : self.stubResponse(#"{"groups":[\#(self.version("4.1.0", "105", events: 40, users: 7, total: 20)),"#
                    + self.version("4.0.1", "106", events: 30, users: 1, total: 0) + "]}")
        }

        let rows = try await makeClient(httpClient).fetchBreakdown(
            issueId: "I1", dimension: .version, interval: TestWindow.interval)

        // Equal events: name breaks the tie ("4.0.0 (101)" < "4.0.1 (106)").
        #expect(rows.map(\.name) == ["4.1.0 (105)", "4.0.0 (101)", "4.0.1 (106)"])
        #expect(rows.map(\.eventsCount) == [40, 30, 30])
        #expect(rows.map { $0.eventsShare } == [40, 30, 30])
        #expect(rows.map(\.impactedUsersCount) == [7, 3, 1])
        #expect(rows.map(\.versionUsersCount) == [20, 300, 0])
        // impacted / version users; a version without users gets no percentage.
        #expect(rows.map(\.impactedUsersPercentage) == [35, 1, nil])
        #expect(rows[0].displayVersion == "4.1.0")
        #expect(rows[0].buildVersion == "105")
        #expect(rows[0].crashFreeUsersPercentage == nil)

        #expect(httpClient.requests.count == 2)
        let first = try #require(httpClient.requests.first?.url)
        #expect(first.path == "/v1alpha/projects/623140959935/apps/\(appId)/reports/topVersions")
        #expect(first.issuesQueryItem(named: "filter.issue.id") == "I1")
        #expect(first.issuesQueryItem(named: "filter.interval.startTime") == TestWindow.startQuery)
        #expect(first.issuesQueryItem(named: "filter.interval.endTime") == TestWindow.endQuery)
        #expect(first.issuesQueryItem(named: "page_size") == "100")
        #expect(first.issuesQueryItem(named: "page_token") == nil)
        #expect(httpClient.requests.last?.url?.issuesQueryItem(named: "page_token") == "P2")
    }

    @Test("app-wide versions send no issue filter and carry crash-free users and sessions")
    func versionsAppWide() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(#"{"groups":[\#(self.version("4.1.0", "105", events: 8, users: 2, total: 19911, crashFree: 85.48))]}"#)
        }

        let rows = try await makeClient(httpClient).fetchBreakdown(issueId: nil, dimension: .version, interval: TestWindow.interval)

        let row = try #require(rows.first)
        #expect(row.versionUsersCount == 19911)
        #expect(row.crashFreeUsersPercentage == 85.48)
        #expect(row.sessionsCount == 8)
        #expect(row.totalSessionsCount == 199_110)
        #expect(row.impactedUsersPercentage == nil)
        let url = try #require(httpClient.requests.first?.url)
        #expect(url.issuesQueryItem(named: "filter.issue.id") == nil)
        #expect(url.issuesQueryItem(named: "filter.interval.startTime") == TestWindow.startQuery)
    }

    @Test("operating systems: reads the display name and, with an issue filter, claims no population")
    func operatingSystemsForIssue() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(#"""
            {"groups":[
              {"operatingSystem":{"displayVersion":"27.2.0","os":"iOS","displayName":"iOS (27.2.0)"},
               "metrics":[{"eventsCount":"9","impactedUsersCount":"4","totalUsersCount":"4","crashFreeUsersPercentage":50}]},
              {"operatingSystem":{"displayVersion":"26.0","os":"iOS"},"metrics":[{"eventsCount":"1","impactedUsersCount":"1"}]},
              {"metrics":[{"eventsCount":"5"}]}]}
            """#)
        }

        let rows = try await makeClient(httpClient).fetchBreakdown(issueId: "I1", dimension: .os, interval: TestWindow.interval)

        #expect(rows.map(\.name) == ["iOS (27.2.0)", "iOS (26.0)"])
        #expect(rows[0].os == "iOS")
        #expect(rows[0].osVersion == "27.2.0")
        #expect(rows.map(\.usersCount) == [nil, nil])
        #expect(rows.map(\.crashFreeUsersPercentage) == [nil, nil])
        #expect(httpClient.requests.first?.url?.path.hasSuffix("/reports/topOperatingSystems") == true)
    }

    @Test("app-wide operating systems report a population only when Crashlytics sends crash-free users with it")
    func operatingSystemsAppWide() async throws {
        let httpClient = FakeHTTPClient { _ in
            self.stubResponse(#"""
            {"groups":[
              {"operatingSystem":{"displayName":"iOS (27.2.0)"},
               "metrics":[{"eventsCount":"90","impactedUsersCount":"9","totalUsersCount":"9"}]},
              {"operatingSystem":{"displayName":"iOS (26.6.2)"},
               "metrics":[{"eventsCount":"10","impactedUsersCount":"5","totalUsersCount":"500","crashFreeUsersPercentage":99}]}]}
            """#)
        }

        let rows = try await makeClient(httpClient).fetchBreakdown(issueId: nil, dimension: .os, interval: TestWindow.interval)

        #expect(rows.map(\.usersCount) == [nil, 500])
        #expect(rows.map(\.crashFreeUsersPercentage) == [nil, 99])
    }

    @Test("devices: model subgroups are flattened across manufacturers and pages, then ranked together")
    func devicesFlattenSubgroups() async throws {
        let counter = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            counter.next() == 1
                ? self.stubResponse(#"""
                {"groups":[{"metrics":[{"eventsCount":"60"}],"device":{"manufacturer":"Apple","displayName":"Apple"},
                  "subgroups":[
                   {"metrics":[{"eventsCount":"40","impactedUsersCount":"4"}],
                    "device":{"manufacturer":"Apple","model":"iPhone18,2","displayName":"Apple (iPhone18,2)","marketingName":"iPhone 17 Pro Max"}},
                   {"metrics":[{"eventsCount":"0"}],"device":{"manufacturer":"Apple","model":"iPhone1,1","displayName":"Apple (iPhone1,1)"}},
                   {"metrics":[{"eventsCount":"20","impactedUsersCount":"2"}],
                    "device":{"manufacturer":"Apple","model":"iPhone17,2","displayName":"Apple (iPhone17,2)"}}]}],
                 "nextPageToken":"P2"}
                """#)
                : self.stubResponse(#"""
                {"groups":[{"metrics":[{"eventsCount":"40"}],"device":{"manufacturer":"Google","displayName":"Google"},
                  "subgroups":[{"metrics":[{"eventsCount":"40","impactedUsersCount":"6"}],
                    "device":{"manufacturer":"Google","model":"Pixel 9","displayName":"Google (Pixel 9)"}}]}]}
                """#)
        }

        let rows = try await makeClient(httpClient).fetchBreakdown(issueId: "I1", dimension: .device, interval: TestWindow.interval)

        #expect(rows.map(\.name) == ["Apple (iPhone18,2)", "Google (Pixel 9)", "Apple (iPhone17,2)"])
        #expect(rows.map(\.eventsCount) == [40, 40, 20])
        #expect(rows.map(\.eventsShare) == [40, 40, 20])
        #expect(rows[0].model == "iPhone18,2")
        #expect(rows[0].manufacturer == "Apple")
        #expect(rows[0].marketingName == "iPhone 17 Pro Max")
        #expect(rows.map(\.eventsCount).reduce(0, +) == 100)
        #expect(httpClient.requests.first?.url?.path.hasSuffix("/reports/topAppleDevices") == true)
    }

    @Test("an issue id outside the allowed characters is rejected before any request")
    func rejectsBadIssueId() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(#"{"groups":[]}"#) }
        await #expect(throws: CrashlyticsClientError.self) {
            _ = try await makeClient(httpClient).fetchBreakdown(issueId: "a/b", dimension: .version, interval: TestWindow.interval)
        }
        #expect(httpClient.requests.isEmpty)
    }

    @Test("a report without events yields no rows")
    func emptyReport() async throws {
        let httpClient = FakeHTTPClient { _ in self.stubResponse(#"{"groups":[\#(self.version("4.0.0", "1", events: 0, users: 0, total: 5))]}"#) }
        #expect(try await makeClient(httpClient).fetchBreakdown(issueId: "I1", dimension: .version, interval: TestWindow.interval).isEmpty)
    }

    @Test("VersionRange is the lowest and highest version with events, ordered as versions, builds breaking ties")
    func versionRange() {
        func row(_ display: String, _ build: String, _ events: Int) -> BreakdownRow {
            BreakdownRow(
                dimension: .version, name: "\(display) (\(build))", displayVersion: display, buildVersion: build,
                eventsCount: events, impactedUsersCount: 0)
        }
        let rows = [row("4.10.0", "7", 1), row("4.2.0", "9", 5), row("4.2.0", "3", 2), row("1.0.0", "1", 0), row("4.10.0", "12", 1)]

        let range = VersionRange(rows)

        #expect(range?.min == "4.2.0 (3)")
        #expect(range?.max == "4.10.0 (12)")
        #expect(VersionRange([row("1.0.0", "1", 0)]) == nil)
        #expect(VersionRange([]) == nil)
    }
}
