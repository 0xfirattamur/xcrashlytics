struct BreakdownPresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = BreakdownTextRenderer()

    func render(_ result: BreakdownResult, format: OutputFormat) throws -> RenderedOutput {
        let payload = BreakdownPayload(result)
        switch format {
        case .text: return RenderedOutput(body: text.render(result))
        case .json: return RenderedOutput(body: try encoder.envelope(payload, warnings: []))
        case .ndjson: return RenderedOutput(body: try encoder.ndjson(payload.items.map(BreakdownRecord.init)))
        }
    }
}
