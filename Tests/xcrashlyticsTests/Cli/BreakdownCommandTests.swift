import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics breakdown")
struct BreakdownCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    /// Two versions with events and one without, as an issue-filtered topVersions report.
    private static let versionsReport = #"""
    {"groups":[
      {"version":{"displayVersion":"4.0.0","buildVersion":"101","displayName":"4.0.0 (101)"},
       "metrics":[{"eventsCount":"25","impactedUsersCount":"5","sessionsCount":"25","totalUsersCount":"500"}]},
      {"version":{"displayVersion":"3.0.0","buildVersion":"1","displayName":"3.0.0 (1)"},
       "metrics":[{"eventsCount":"0","impactedUsersCount":"0","totalUsersCount":"900"}]},
      {"version":{"displayVersion":"4.1.0","buildVersion":"105","displayName":"4.1.0 (105)"},
       "metrics":[{"eventsCount":"75","impactedUsersCount":"20","sessionsCount":"74","totalUsersCount":"20000"}]}]}
    """#

    private func context(_ httpClient: FakeHTTPClient, console: SpyConsole = SpyConsole()) throws -> Platform {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(), console: console)
            .withFirebaseHTTP(httpClient)
    }

    private func httpClient(_ body: String = versionsReport) -> FakeHTTPClient {
        FakeHTTPClient { request in FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8)) }
    }

    @Test("an issue's versions: JSON rows, totals, version range, canonical id, and the request's query")
    func issueVersionsJSON() async throws {
        let transport = httpClient()
        let output = try await BreakdownCommand.parse(["FB-I1", "--by", "version", "--since", "30d", "--format", "json"])
            .execute(context(transport).container)

        let data = try Envelope(output).data
        #expect(data["dimension"]?.string == "version")
        #expect(data["issueId"]?.string == "FB-I1")
        #expect(data["since"]?.string == "30d")
        #expect(data["eventsCount"]?.int == 100)
        #expect(data["groupCount"]?.int == 2)
        #expect(data["versionRange"]?["min"]?.string == "4.0.0 (101)")
        #expect(data["versionRange"]?["max"]?.string == "4.1.0 (105)")
        #expect(data["window"]?["since"]?.string == "1969-12-13T13:46:40Z")
        let items = try #require(data["items"]?.array)
        #expect(items.compactMap { $0["name"]?.string } == ["4.1.0 (105)", "4.0.0 (101)"])
        #expect(items[0]["eventsCount"]?.int == 75)
        #expect(items[0]["eventsShare"]?.double == 75)
        #expect(items[0]["versionUsersCount"]?.int == 20000)
        #expect(items[0]["impactedUsersCount"]?.int == 20)
        #expect(items[0]["impactedUsersPercentage"]?.double == 0.1)
        #expect(items[1]["impactedUsersPercentage"]?.double == 1)

        let request = try #require(transport.requests.first?.url)
        #expect(request.path.hasSuffix("/reports/topVersions"))
        #expect(request.issuesQueryItem(named: "filter.issue.id") == "I1")
        #expect(request.issuesQueryItem(named: "filter.interval.startTime") == "1969-12-13T13:46:40Z")
        #expect(request.issuesQueryItem(named: "filter.interval.endTime") == "1970-01-12T13:46:40Z")
    }

    @Test("the window defaults to 7d, all means 90d, and a window beyond 90d fails before any request")
    func windows() async throws {
        let transport = httpClient()
        _ = try await BreakdownCommand.parse(["FB-I1", "--by", "version", "--format", "json"]).execute(context(transport).container)
        _ = try await BreakdownCommand.parse(["FB-I1", "--by", "version", "--since", "all", "--format", "json"])
            .execute(context(transport).container)
        let starts = transport.requests.compactMap { $0.url?.issuesQueryItem(named: "filter.interval.startTime") }
        #expect(starts == ["1970-01-05T13:46:40Z", "1969-10-14T13:46:40Z"])

        let strict = FakeHTTPClient { _ in throw HTTPTransportError.transport("no request expected") }
        await #expect(throws: InvalidInputError.self) {
            _ = try await BreakdownCommand.parse(["FB-I1", "--by", "os", "--since", "120d"]).execute(context(strict).container)
        }
        #expect(strict.requests.isEmpty)
    }

    @Test("--limit keeps the top rows but totals, shares and the version range still cover every group")
    func limitKeepsTotals() async throws {
        let output = try await BreakdownCommand.parse(["FB-I1", "--by", "version", "--limit", "1", "--format", "json"])
            .execute(context(httpClient()).container)

        let data = try Envelope(output).data
        #expect(data["items"]?.array?.count == 1)
        #expect(data["groupCount"]?.int == 2)
        #expect(data["eventsCount"]?.int == 100)
        #expect(data["versionRange"]?["min"]?.string == "4.0.0 (101)")
        #expect(data["items"]?[0]?["eventsShare"]?.double == 75)
    }

    @Test("--limit 0 fails before any request")
    func limitMustBePositive() async throws {
        let transport = httpClient()
        await #expect(throws: ValidationError.self) {
            _ = try await BreakdownCommand.parse(["FB-I1", "--by", "version", "--limit", "0"]).execute(context(transport).container)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("app-wide: no issue filter, no issueId, crash-free users in the rows")
    func appWide() async throws {
        let body = #"""
        {"groups":[{"version":{"displayVersion":"4.1.0","buildVersion":"105","displayName":"4.1.0 (105)"},
         "metrics":[{"eventsCount":"9","impactedUsersCount":"3","sessionsCount":"9","totalUsersCount":"19911",
                     "totalSessionsCount":"99999","crashFreeUsersPercentage":85.48}]}]}
        """#
        let transport = httpClient(body)
        let output = try await BreakdownCommand.parse(["--by", "version", "--format", "json"]).execute(context(transport).container)

        let data = try Envelope(output).data
        #expect(data["issueId"] == nil)
        let row = try #require(data["items"]?[0])
        #expect(row["versionUsersCount"]?.int == 19911)
        #expect(row["crashFreeUsersPercentage"]?.double == 85.48)
        #expect(row["impactedUsersPercentage"] == nil)
        #expect(transport.requests.first?.url?.issuesQueryItem(named: "filter.issue.id") == nil)
    }

    @Test("ids: event ids name their issue, malformed ids are BAD_INPUT")
    func idHandling() async throws {
        let transport = httpClient()
        _ = try await BreakdownCommand.parse(["fb-I1/events/E9", "--by", "version", "--format", "json"])
            .execute(context(transport).container)
        #expect(transport.requests.first?.url?.issuesQueryItem(named: "filter.issue.id") == "I1")

        await #expect(throws: InvalidInputError.self) {
            _ = try await BreakdownCommand.parse(["XC-1", "--by", "version"]).execute(context(transport).container)
        }
        #expect(transport.requests.count == 1)
    }

    @Test("a console link selects the profile whose bundle id matches the link")
    func consoleLink() async throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(
            appId: "1:111:ios:aaa",
            profiles: ["main": AppProfile(appId: "1:222:ios:bbb", bundleId: "com.example.app")]))
        let transport = httpClient()
        let linked = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
            .withFirebaseHTTP(transport)
        let link = "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.example.app/issues/I7"

        _ = try await BreakdownCommand.parse([link, "--by", "version", "--format", "json"]).execute(linked.container)

        let url = try #require(transport.requests.first?.url)
        #expect(url.path.contains("/apps/1:222:ios:bbb/"))
        #expect(url.issuesQueryItem(named: "filter.issue.id") == "I7")
    }
}
