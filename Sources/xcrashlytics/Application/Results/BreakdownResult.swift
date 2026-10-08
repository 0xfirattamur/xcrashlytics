import Foundation

struct BreakdownResult: Sendable {
    var dimension: BreakdownDimension
    /// nil for the app-wide report.
    var issueId: String?
    var since: String
    var window: DateInterval
    /// Totals cover every row; `rows` is what survived `--limit`.
    var eventsCount: Int
    var groupCount: Int
    var versionRange: VersionRange?
    var rows: [BreakdownRow]
}
