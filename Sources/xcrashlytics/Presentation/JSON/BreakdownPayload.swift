import Foundation

struct BreakdownPayload: Encodable, Sendable {
    var dimension: String
    var issueId: String?
    var since: String
    var window: ReportWindowSummary
    /// Events of all groups of the report window (before `--limit`); the rows' `eventsShare` is relative to it.
    var eventsCount: Int
    var groupCount: Int
    var versionRange: VersionRangePayload?
    var items: [BreakdownRowPayload]

    init(_ result: BreakdownResult) {
        dimension = result.dimension.rawValue
        issueId = result.issueId
        since = result.since
        window = ReportWindowSummary(result.window)
        eventsCount = result.eventsCount
        groupCount = result.groupCount
        versionRange = result.versionRange.map(VersionRangePayload.init)
        items = result.rows.map(BreakdownRowPayload.init)
    }
}
