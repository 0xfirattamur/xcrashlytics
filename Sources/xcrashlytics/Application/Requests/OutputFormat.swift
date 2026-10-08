enum OutputFormat: String, CaseIterable, Sendable {
    case text
    case json
    case ndjson

    var isJSON: Bool { self != .text }
}
