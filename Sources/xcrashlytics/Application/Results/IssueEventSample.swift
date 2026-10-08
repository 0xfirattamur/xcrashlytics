import Foundation

struct IssueEventSample: Sendable {
    var index: Int
    var issue: CrashIssue
    var events: [CrashlyticsEvent]
    /// Set when best-effort sampling failed; `events` is then empty.
    var failure: String?
}
