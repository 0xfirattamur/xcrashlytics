enum ExportFormat: String, CaseIterable, Sendable {
    case markdown
    case json

    var outputFormat: OutputFormat { self == .json ? .json : .text }
}
