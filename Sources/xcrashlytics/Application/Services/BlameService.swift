struct BlameService: Sendable {
    let clients: CrashlyticsClientProvider
    let frameSelectors: ProfileFrameSelector
    let dateProvider: DateProvider

    func blame(_ request: BlameRequest) async throws -> BlameResult {
        let window = try ReportWindow(since: request.since, now: dateProvider.currentDate()).interval
        let client = try clients.client()
        let issues = try await client.fetchIssues(
            limit: request.issueLimit, interval: window, options: IssueQueryOptions())

        let sampler = IssueEventSampler(
            firebase: client,
            eventsPerIssue: request.eventsPerIssue,
            interval: window,
            concurrency: request.concurrency)
        let samples = try await sampler.sample(issues: issues)

        let aggregator = BlameAggregator(
            top: request.top, windowStart: window.start, frameSelector: frameSelectors.selector())
        let aggregation = aggregator.aggregate(samples.map { ($0.issue, $0.events) })
        return BlameResult(
            request: request,
            window: window,
            issuesScanned: issues.count,
            sampledEvents: aggregation.sampledEvents,
            rows: aggregation.rows)
    }
}
