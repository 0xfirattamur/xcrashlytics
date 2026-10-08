import Foundation

struct JSONPayloadEncoder: Sendable {
    func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    func ndjsonLine<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func envelope<T: Encodable>(_ data: T, warnings: [CommandWarning]) throws -> String {
        try json(JSONEnvelope(data: data, warnings: warnings.map(WarningPayload.init)))
    }

    func ndjson<T: Encodable>(_ records: [T]) throws -> String {
        guard !records.isEmpty else { return "" }
        return try records.map { try ndjsonLine(VersionedRecord(value: $0)) }.joined(separator: "\n") + "\n"
    }
}
