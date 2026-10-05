import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case text
    case json
    case ndjson

    var isJSON: Bool { self != .text }
}
