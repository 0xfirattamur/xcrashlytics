import Foundation
import Testing

/// A decoded JSON value with optional-chaining accessors:
/// `try JSON.parse(out)["data"]?["issues"]?[0]?["id"]?.string`.
enum JSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSON].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: JSON].self))
        }
    }

    static func parse(_ text: String) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: Data(text.utf8))
    }

    /// One value per non-empty NDJSON line.
    static func lines(_ text: String) throws -> [JSON] {
        try text.split(separator: "\n").map { try parse(String($0)) }
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    subscript(index: Int) -> JSON? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    var string: String? { if case .string(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var int: Int? { if case .number(let v) = self { return Int(exactly: v) }; return nil }
    var double: Double? { if case .number(let v) = self { return v }; return nil }
    var array: [JSON]? { if case .array(let v) = self { return v }; return nil }
    var object: [String: JSON]? { if case .object(let v) = self { return v }; return nil }
}

/// A parsed success envelope. Parsing asserts the v1 contract shape.
struct Envelope {
    let data: JSON
    let warnings: [JSON]

    init(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let root = try JSON.parse(text)
        #expect(root["schemaVersion"]?.int == 1, "missing schemaVersion 1", sourceLocation: sourceLocation)
        #expect(root["error"] == nil, "expected success, got error envelope", sourceLocation: sourceLocation)
        data = try #require(root["data"], "missing data", sourceLocation: sourceLocation)
        warnings = try #require(root["warnings"]?.array, "missing warnings array", sourceLocation: sourceLocation)
    }

    var warningCodes: [String] { warnings.compactMap { $0["code"]?.string } }
}
