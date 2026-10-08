import Foundation

/// Only RFC 3986 unreserved characters pass through, so `+`, `&`, `=`, and `%` in a value
/// (a refresh token, a page token) can never be misread by the server.
enum FormURLEncoder {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    // Query values also keep characters that carry no meaning inside a value, so timestamps stay readable.
    private static let queryValue = unreserved.union(CharacterSet(charactersIn: ":/@,"))

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValue) ?? value
    }

    // Sorted by name so bodies are deterministic.
    static func body(_ fields: [String: String]) -> Data {
        let pairs = fields.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\(encode($0.value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
