import Foundation
import Testing
@testable import xcrashlytics

/// `export`'s exact version / OS / device spreads, built on `ExportCommandTests`' fixtures.
extension ExportCommandTests {
    @Test("JSON carries the exact breakdown and versionRange next to the unchanged sample")
    func exportsBreakdownJSON() async throws {
        let httpClient = firebaseHTTP()
        let json = try Envelope(try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(httpClient).container))

        let breakdown = try #require(json.data["breakdown"])
        #expect(breakdown["versions"]?.array?.compactMap { $0["name"]?.string } == ["6.16.0 (937)", "6.15.0 (930)"])
        #expect(breakdown["versions"]?[0]?["versionUsersCount"]?.int == 400)
        #expect(breakdown["versions"]?[0]?["impactedUsersPercentage"]?.double == 1)
        #expect(breakdown["operatingSystems"]?.array?.compactMap { $0["eventsCount"]?.int } == [13, 2])
        #expect(breakdown["operatingSystems"]?[0]?["versionUsersCount"] == nil)
        #expect(breakdown["devices"]?.array?.compactMap { $0["model"]?.string } == ["iPhone17,1", "iPhone15,2"])
        #expect(breakdown["window"]?["since"]?.string == "1970-01-05T13:46:40Z")
        #expect(json.data["versionRange"]?["min"]?.string == "6.15.0 (930)")
        #expect(json.data["versionRange"]?["max"]?.string == "6.16.0 (937)")
        #expect(json.data["sample"]?["versionSpread"]?.array?.count == 2)
        #expect(json.warnings.isEmpty)

        let reports = httpClient.requests.compactMap { $0.url }.filter { $0.path.contains("/reports/top") && !$0.path.hasSuffix("topIssues") }
        #expect(reports.map(\.lastPathComponent).sorted() == ["topAppleDevices", "topOperatingSystems", "topVersions", "topVersions"])
        for url in reports where url.lastPathComponent != "topVersions" {
            #expect(url.issuesQueryItem(named: "filter.issue.id") == "I1")
            #expect(url.issuesQueryItem(named: "filter.interval.startTime") == "1970-01-05T13:46:40Z")
        }
    }

    @Test("only the top five rows per dimension are exported; the version range still covers every version")
    func exportKeepsTopFive() async throws {
        let groups = (1...7).map { index in
            #"{"version":{"displayVersion":"1.\#(index).0","buildVersion":"\#(index)","displayName":"1.\#(index).0 (\#(index))"},"#
                + #""metrics":[{"eventsCount":"\#(index)","impactedUsersCount":"1","totalUsersCount":"10"}]}"#
        }.joined(separator: ",")
        let inner = firebaseHTTP()
        let httpClient = FakeHTTPClient { request in
            let isPlainVersions = request.url?.path.hasSuffix("/reports/topVersions") == true
                && request.url?.issuesQueryItem(named: "granularity") == nil
            guard isPlainVersions else { return try inner.handler!(request) }
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"groups":[\#(groups)]}"#.utf8))
        }

        let data = try Envelope(try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(httpClient).container)).data

        #expect(data["breakdown"]?["versions"]?.array?.compactMap { $0["eventsCount"]?.int } == [7, 6, 5, 4, 3])
        #expect(data["versionRange"]?["min"]?.string == "1.1.0 (1)")
        #expect(data["versionRange"]?["max"]?.string == "1.7.0 (7)")
    }

    @Test("a failing report falls back to the sampled spread for that dimension and warns BREAKDOWN_UNAVAILABLE")
    func breakdownFallsBackToSample() async throws {
        let httpClient = firebaseHTTP(failingReports: ["topAppleDevices"])

        let json = try Envelope(try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(httpClient).container))
        let console = SpyConsole()
        let report = try await ExportCommand.parse(["FB-I1"]).execute(context(httpClient, console: console).container)

        #expect(json.warningCodes == ["BREAKDOWN_UNAVAILABLE"])
        #expect(json.warnings.first?["message"]?.string?.contains("device report failed") == true)
        #expect(json.data["breakdown"]?["devices"] == nil)
        #expect(json.data["breakdown"]?["versions"]?.array?.count == 2)
        #expect(json.data["sample"]?["deviceSpread"]?.array?.count == 2)
        #expect(report.contains("- Devices: "))
        #expect(report.contains("Sampled instead (newest 2 events, not exact):"))
        #expect(report.contains("- Devices: iPhone 16 ×1, iPhone 17 Pro Max ×1"))
        #expect(!report.contains("Apple (iPhone15,2)"))
        #expect(console.warnings.contains { $0.hasPrefix("BREAKDOWN_UNAVAILABLE:") })
    }

    @Test("when every report fails the export keeps the sample and warns once per dimension")
    func allBreakdownsFail() async throws {
        let httpClient = firebaseHTTP(failingReports: ["topOperatingSystems", "topAppleDevices"])
        let inner = httpClient.handler!
        let versionsDown = FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/reports/topVersions") == true, request.url?.issuesQueryItem(named: "granularity") == nil {
                return FakeHTTPClient.response(request.url!, status: 400, body: Data(#"{"error":{"message":"down"}}"#.utf8))
            }
            return try inner(request)
        }

        let json = try Envelope(try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(versionsDown).container))

        #expect(json.warningCodes == ["BREAKDOWN_UNAVAILABLE", "BREAKDOWN_UNAVAILABLE", "BREAKDOWN_UNAVAILABLE"])
        #expect(json.data["breakdown"] == nil)
        #expect(json.data["versionRange"] == nil)
        #expect(json.data["sample"]?["versionSpread"]?.array?.count == 2)
    }
}
