//
//  JSONEnvelope.swift
//  xcrashlytics
//

import XCrashlyticsCore

/// Version of the JSON / NDJSON output contract. Bumped only on breaking changes.
let outputSchemaVersion = 1

/// A non-fatal problem reported alongside a successful result.
struct CLIWarning: Encodable, Equatable, Sendable {
    /// Stable machine code, e.g. `XCODE_PARSE_FAILED`, `SEARCH_TRUNCATED`.
    var code: String
    var message: String
    var path: String?

    init(code: String, message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }

    init(_ warning: CrashLoadWarning) {
        self.init(code: warning.code, message: warning.message, path: warning.path)
    }
}

/// `{ "schemaVersion": 1, "data": …, "warnings": [...] }` — every successful
/// `--format json` result.
struct JSONEnvelope<T: Encodable>: Encodable {
    var schemaVersion = outputSchemaVersion
    var data: T
    var warnings: [CLIWarning]
}

/// One NDJSON record: the value's own keys plus `schemaVersion`.
struct VersionedRecord<T: Encodable>: Encodable {
    var value: T

    private enum CodingKeys: String, CodingKey { case schemaVersion }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputSchemaVersion, forKey: .schemaVersion)
    }
}

extension PayloadEncoder {
    /// Pretty-printed success envelope.
    static func envelope<T: Encodable>(_ data: T, warnings: [CLIWarning]) throws -> String {
        try json(JSONEnvelope(data: data, warnings: warnings))
    }

    /// One NDJSON line per record, each carrying `schemaVersion`.
    static func ndjson<T: Encodable>(_ records: [T]) throws -> String {
        guard !records.isEmpty else { return "" }
        return try records.map { try ndjsonLine(VersionedRecord(value: $0)) }.joined(separator: "\n") + "\n"
    }
}

extension CommandContext {
    /// Non-JSON formats report warnings on stderr; JSON embeds them instead.
    func report(_ warnings: [CLIWarning], format: OutputFormat) {
        guard format != .json else { return }
        for warning in warnings { console.warn(warning.message) }
    }
}
