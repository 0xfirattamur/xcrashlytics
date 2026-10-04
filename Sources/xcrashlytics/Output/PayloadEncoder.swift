import Foundation
import XCrashlyticsCore

/// The one JSON configuration every CLI payload uses, so field formatting
/// never drifts between commands.
public enum PayloadEncoder {
    public static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    public static func ndjsonLine<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
