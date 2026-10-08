struct ExportPresenter {
    var encoder = JSONPayloadEncoder()
    var markdown = MarkdownRenderer()
    var toolVersion: String

    func render(_ result: CrashExportResult, format: ExportFormat) throws -> RenderedOutput {
        let report = ExportReport(result, toolVersion: toolVersion)
        let body: String
        switch format {
        case .markdown:
            body = markdown.render(report)
        case .json:
            body = try encoder.envelope(ExportReportPayload(report), warnings: result.warnings)
        }
        return RenderedOutput(body: body, warnings: result.warnings)
    }

    func confirmation(for result: CrashExportResult, writtenTo path: String) -> String {
        "Exported \(result.detail.event.id) to \(path).\n"
    }
}
