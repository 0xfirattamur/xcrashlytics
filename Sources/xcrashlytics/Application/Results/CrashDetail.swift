import Foundation

struct CrashDetail {
    var event: CrashEvent
    var issue: CrashIssue?
    var activity: IssueActivitySummary?
    var firebaseEvent: CrashlyticsEvent?
    var latestEvent: CrashlyticsEvent?
    var impact: IssueImpact?
    var dailyEvents: [DailyEventCount]?
    /// Newest first; empty for `XC-` ids.
    var sampledEvents: [CrashlyticsEvent] = []
    var versionRange: VersionRange?
    var warnings: [CommandWarning] = []
    /// What the service applied, so presenters select the same frames.
    var frameFilter = FrameFilter.none
    var frameSelector = FrameSelector()
}
