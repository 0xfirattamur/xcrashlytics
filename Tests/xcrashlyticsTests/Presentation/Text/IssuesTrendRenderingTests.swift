import Foundation
import Testing
@testable import xcrashlytics

@Suite("Issues trend rendering")
struct IssuesTrendRenderingTests {
    private func issue(_ id: String, eventsCount: Int?, days: [DailyEventCount]? = nil) -> CrashIssue {
        CrashIssue(
            providerId: id, exceptionType: "EXC_BAD_ACCESS", eventsCount: eventsCount, impactedUsersCount: 1,
            dailyEvents: days)
    }

    private func text(_ issues: [CrashIssue]) -> String {
        IssuesTextRenderer().render(
            issues: issues, xcodeCrashes: [], hint: nil, symbolicationHint: nil, lastSeenAt: [:])
    }

    @Test("the report's daily counts render exactly, with no sampling or lower-bound marks")
    func dailyCountsAreExact() {
        let days = [
            DailyEventCount(day: "2026-06-09", eventsCount: 2),
            DailyEventCount(day: "2026-06-10", eventsCount: 98)
        ]
        let output = text([issue("I1", eventsCount: 100, days: days)])
        #expect(output.contains("2026-06-09:2,2026-06-10:98"))
        #expect(!output.contains("≥"))
        #expect(!output.contains("sampled"))
    }

    @Test("version column words first and last seen, never a range")
    func seenVersionsAreNotARange() {
        let spanning = CrashIssue(
            providerId: "I1", exceptionType: "EXC_BAD_ACCESS", eventsCount: 10, impactedUsersCount: 1,
            firstSeenVersion: "6.22.0", lastSeenVersion: "5.3.1")
        let output = text([spanning])
        #expect(output.contains("FB-I1   EXC_BAD_ACCESS   first seen 6.22.0 · last seen 5.3.1"))
        #expect(!output.contains("→"))
    }

    @Test("issue summary reports the daily series as exact: sampled count is the sum, never truncated")
    func issueSummaryTrendFields() throws {
        let days = [
            DailyEventCount(day: "2026-06-09", eventsCount: 2),
            DailyEventCount(day: "2026-06-10", eventsCount: 98)
        ]
        let summary = IssueSummary(issue("I1", eventsCount: 100, days: days))
        let json = try JSON.parse(JSONPayloadEncoder().json(summary))
        #expect(json["dailyEventsSampledCount"]?.int == 100)
        #expect(json["dailyEventsTruncated"]?.bool == false)
        #expect(json["dailyEvents"]?[0]?["day"]?.string == "2026-06-09")
        #expect(json["dailyEvents"]?[1]?["eventsCount"]?.int == 98)
    }

    @Test("without --by-day the summary has no trend fields")
    func issueSummaryWithoutSeries() throws {
        let json = try JSON.parse(JSONPayloadEncoder().json(IssueSummary(issue("I1", eventsCount: 10))))
        #expect(json["dailyEvents"] == nil)
        #expect(json["dailyEventsSampledCount"] == nil)
        #expect(json["dailyEventsTruncated"] == nil)
    }
}
