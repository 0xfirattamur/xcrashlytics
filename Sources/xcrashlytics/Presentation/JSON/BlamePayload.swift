struct BlamePayload: Encodable, Sendable {
    var since: String
    var window: ReportWindowSummary
    var issueLimit: Int
    var eventsPerIssue: Int
    var concurrency: Int
    var top: Int
    var issuesScanned: Int
    /// Events that fell inside the cutoff and entered the aggregation. Every
    /// `eventCount` below counts these sampled events, not Firebase totals.
    var sampledEvents: Int
    var items: [BlameItem]

}
