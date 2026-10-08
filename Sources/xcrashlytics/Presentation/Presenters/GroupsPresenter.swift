struct GroupsPresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = GroupsTextRenderer()

    func render(_ result: GroupsResult, format: OutputFormat) throws -> RenderedOutput {
        switch format {
        case .text:
            return RenderedOutput(body: text.render(result.groups), warnings: result.warnings)
        case .json:
            let payload = GroupsPayload(
                window: ReportWindowSummary(result.window), groups: result.groups.map(GroupRecord.init))
            return RenderedOutput(
                body: try encoder.envelope(payload, warnings: result.warnings), warnings: result.warnings)
        case .ndjson:
            throw InvalidInputError("--format ndjson is not supported by this command.")
        }
    }
}
