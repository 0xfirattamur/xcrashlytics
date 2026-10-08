import Foundation

/// Privacy: drops user-id keys and values equal to the event's user id, and blanks
/// the id inside longer text.
struct CustomKeyRedactor: Sendable {
    var userId: String?

    static let userKeyNames: Set<String> = ["userid", "user_id", "user-id", "uid"]
    static let placeholder = "[redacted]"

    private var knownUserId: String? {
        userId?.trimmedNonEmpty
    }

    func isUserKey(_ key: String) -> Bool {
        Self.userKeyNames.contains(key.lowercased())
    }

    func scrub(_ text: String) -> String {
        guard let knownUserId, text.contains(knownUserId) else { return text }
        return text.replacingOccurrences(of: knownUserId, with: Self.placeholder)
    }

    func customKeys(_ values: [String: String]) -> [String: String] {
        var redacted: [String: String] = [:]
        for (key, value) in values where !isUserKey(key) {
            if let knownUserId, value.trimmingCharacters(in: .whitespaces) == knownUserId { continue }
            redacted[key] = scrub(value)
        }
        return redacted
    }
}
