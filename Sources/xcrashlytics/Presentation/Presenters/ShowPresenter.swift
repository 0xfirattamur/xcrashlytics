struct ShowPresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = CrashDetailTextRenderer()
    var includeBreadcrumbs = false

    /// Fails before any request when the format cannot be rendered.
    static func requireSupported(_ format: OutputFormat) throws {
        guard format != .ndjson else {
            throw InvalidInputError("--format ndjson is not supported by show; use --format json or text.")
        }
    }

    func render(_ crashDetail: CrashDetail, format: OutputFormat) throws -> RenderedOutput {
        try Self.requireSupported(format)
        let body: String
        if format == .json {
            let payload = ShowPayload(crashDetail, includeBreadcrumbs: includeBreadcrumbs)
            body = try encoder.envelope(payload, warnings: crashDetail.warnings)
        } else {
            body = text.render(crashDetail, includeBreadcrumbs: includeBreadcrumbs)
        }
        return RenderedOutput(body: body, warnings: crashDetail.warnings)
    }
}
