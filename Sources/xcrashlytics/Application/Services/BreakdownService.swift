struct BreakdownService: Sendable {
    let clients: CrashlyticsClientProvider
    let dateProvider: DateProvider

    func breakdown(_ request: BreakdownRequest) async throws -> BreakdownResult {
        let window = try ReportWindow(since: request.since, now: dateProvider.currentDate()).interval
        let target = try request.issue.map { try IssueReportTarget.resolve($0, clients: clients) }
        let client = try target?.client ?? clients.client()
        let rows = try await client.fetchBreakdown(
            issueId: target?.issueId, dimension: request.dimension, interval: window)
        return BreakdownResult(
            dimension: request.dimension,
            issueId: target.map { CrashlyticsIdFormatter.canonicalIssueId($0.issueId) },
            since: request.since,
            window: window,
            eventsCount: rows.reduce(0) { $0 + $1.eventsCount },
            groupCount: rows.count,
            versionRange: request.dimension == .version ? VersionRange(rows) : nil,
            rows: request.limit.map { Array(rows.prefix($0)) } ?? rows)
    }
}
