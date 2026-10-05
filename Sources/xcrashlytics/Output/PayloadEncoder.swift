import Foundation

/// Shared JSON settings for CLI payloads: sorted keys, unescaped slashes and
/// ISO 8601 dates.
enum PayloadEncoder {
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    static func ndjsonLine<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
