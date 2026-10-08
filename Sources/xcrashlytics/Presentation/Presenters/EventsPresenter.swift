struct EventsPresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = EventsTextRenderer()

    func render(_ result: EventsResult, format: OutputFormat) throws -> RenderedOutput {
        let body: String
        switch format {
        case .text:
            body = textBody(result)
        case .json:
            body = try jsonBody(result)
        case .ndjson:
            body = try ndjsonBody(result)
        }
        return RenderedOutput(body: body, warnings: result.warnings)
    }

    // MARK: - Formats

    private func textBody(_ result: EventsResult) -> String {
        let filter = result.request.frameFilter
        let selector = result.frameSelector
        if result.request.showsFramesOnly {
            return text.framesOnlyText(result.issueEvents, filter: filter, selector: selector)
        }
        return text.text(result.issueEvents, filter: filter, selector: selector)
    }

    private func jsonBody(_ result: EventsResult) throws -> String {
        if result.request.showsFramesOnly {
            return try encoder.envelope(payload(result, framesOnlySummaries(result)), warnings: result.warnings)
        }
        return try encoder.envelope(payload(result, summaries(result)), warnings: result.warnings)
    }

    private func ndjsonBody(_ result: EventsResult) throws -> String {
        if result.request.showsFramesOnly {
            return try encoder.ndjson(framesOnlySummaries(result))
        }
        return try encoder.ndjson(summaries(result))
    }

    // MARK: - Payloads

    private func payload<Event>(_ result: EventsResult, _ events: [Event]) -> EventsPayload<Event> {
        EventsPayload(events: events, scannedEvents: result.scan?.scannedEvents, scanDepth: result.scan?.depth)
    }

    private func summaries(_ result: EventsResult) -> [EventSummary] {
        let request = result.request
        return result.issueEvents.flatMap { group in
            group.events.map { event in
                EventSummary(
                    event,
                    issueId: group.issueId,
                    filter: request.frameFilter,
                    selector: result.frameSelector,
                    includeBreadcrumbs: request.includeBreadcrumbs)
            }
        }
    }

    private func framesOnlySummaries(_ result: EventsResult) -> [EventFramesOnlySummary] {
        result.issueEvents.flatMap { group in
            group.events.map { event in
                EventFramesOnlySummary(
                    event,
                    issueId: group.issueId,
                    filter: result.request.frameFilter,
                    selector: result.frameSelector)
            }
        }
    }
}
