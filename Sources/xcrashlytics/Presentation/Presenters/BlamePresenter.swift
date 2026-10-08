struct BlamePresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = BlameTextRenderer()

    func render(_ result: BlameResult, format: OutputFormat) throws -> RenderedOutput {
        let items = result.rows.map(BlameItem.init)
        switch format {
        case .text:
            return RenderedOutput(body: text.render(result.rows))
        case .json:
            let request = result.request
            let payload = BlamePayload(
                since: request.since,
                window: ReportWindowSummary(result.window),
                issueLimit: request.issueLimit,
                eventsPerIssue: request.eventsPerIssue,
                concurrency: request.concurrency,
                top: request.top,
                issuesScanned: result.issuesScanned,
                sampledEvents: result.sampledEvents,
                items: items)
            return RenderedOutput(body: try encoder.envelope(payload, warnings: []))
        case .ndjson:
            return RenderedOutput(body: try encoder.ndjson(items))
        }
    }
}
