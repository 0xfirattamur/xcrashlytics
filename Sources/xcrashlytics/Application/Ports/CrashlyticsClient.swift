import Foundation

protocol CrashlyticsClient: Sendable {
    /// `interval` scopes both ranking and counts; `nil` means the API default, the previous 7 days.
    func fetchIssues(limit: Int?, interval: DateInterval?, options: IssueQueryOptions) async throws -> [CrashIssue]
    /// Newest first. Crashlytics quirk: without an interval the API only reaches back about 7 days.
    func fetchEvents(issueId: String, limit: Int?, interval: DateInterval) async throws -> [CrashlyticsEvent]
    func fetchReportedVersions(interval: DateInterval) async throws -> [ReportedVersion]
    /// Events per UTC day for one issue over `interval`; days without events are omitted.
    func fetchDailyEventCounts(issueId: String, interval: DateInterval) async throws -> [DailyEventCount]
    func fetchIssue(id: String) async throws -> CrashIssue
    /// The issue's event and user totals between `since` and `until`, or `nil`
    /// when it ranks below the first `maxPages` pages of that window's top issues.
    func fetchIssueImpact(issueId: String, since: Date, until: Date, maxPages: Int) async throws -> IssueImpact?
    /// Exact counts per app version, OS version or device model over `interval`,
    /// for one issue or (`issueId` nil) the whole app: events and users only for
    /// groups with events, most events first.
    func fetchBreakdown(
        issueId: String?, dimension: BreakdownDimension, interval: DateInterval
    ) async throws -> [BreakdownRow]
}
