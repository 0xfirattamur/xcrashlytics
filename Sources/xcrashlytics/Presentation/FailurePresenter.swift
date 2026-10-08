struct FailurePresenter: Sendable {
    let console: Console
    var encoder = JSONPayloadEncoder()

    func present(_ failure: CommandFailure, format: OutputFormat) {
        switch format {
        case .text:
            console.writeDiagnostic(textBody(failure))
        case .json:
            console.writeOutput((try? jsonBody(failure)) ?? fallbackBody(failure))
        case .ndjson:
            console.writeOutput((try? ndjsonBody(failure)) ?? fallbackBody(failure))
        }
    }

    /// Last-resort body when encoding itself fails; still a valid versioned record.
    func fallbackBody(_ failure: CommandFailure) -> String {
        "{\"error\":{\"code\":\"\(failure.code)\",\"message\":\"internal error\"},"
            + "\"schemaVersion\":\(outputSchemaVersion)}\n"
    }

    func jsonBody(_ failure: CommandFailure) throws -> String {
        try encoder.json(Payload(failure))
    }

    func ndjsonBody(_ failure: CommandFailure) throws -> String {
        try encoder.ndjsonLine(Payload(failure)) + "\n"
    }

    func textBody(_ failure: CommandFailure) -> String {
        var lines = ["error: \(failure.message)"]
        if let hint = failure.hint {
            lines.append("hint: \(hint)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private struct Payload: Encodable {
        struct Body: Encodable {
            var code: String
            var message: String
            var hint: String?
        }
        var schemaVersion = outputSchemaVersion
        var error: Body

        init(_ failure: CommandFailure) {
            error = Body(code: failure.code, message: failure.message, hint: failure.hint)
        }
    }
}
