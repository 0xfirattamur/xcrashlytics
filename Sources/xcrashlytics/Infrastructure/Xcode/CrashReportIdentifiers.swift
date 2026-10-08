import Foundation

enum CrashReportIdentifiers {
    static func normalisedUUID(_ raw: String) -> String {
        // Legacy reports use 32 hex chars without dashes; dSYM UUIDs are 8-4-4-4-12.
        let hex = raw.replacingOccurrences(of: "-", with: "").uppercased()
        guard hex.count == 32 else { return raw.uppercased() }
        let digits = Array(hex)
        let groupRanges = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        return groupRanges.map { String(digits[$0]) }.joined(separator: "-")
    }

    // Incident ids become `XC-<id>` CLI ids, so they must be one shell-safe token.
    static func sanitizedIncidentId(_ raw: String?) -> String? {
        guard let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty, id.count <= 128,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") })
        else { return nil }
        return id
    }

    // Deterministic: the same file must map to the same id across rescans or grouping breaks.
    static func stableFallbackId(for text: String) -> String {
        String(SHA256Hasher.hexDigest(of: text).prefix(32)).uppercased()
    }
}
