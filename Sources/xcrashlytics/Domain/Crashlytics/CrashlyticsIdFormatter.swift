import Foundation

enum CrashlyticsIdFormatter {
    private static let prefix = "FB-"

    private static func hasPrefix(_ value: String) -> Bool {
        value.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }

    static func issueId(from canonical: String) -> String {
        hasPrefix(canonical) ? String(canonical.dropFirst(prefix.count)) : canonical
    }

    static func canonicalIssueId(_ issueId: String) -> String {
        prefix + Self.issueId(from: issueId)
    }

    static func isCanonicalLike(_ value: String) -> Bool { hasPrefix(value) }

    static func canonicalEventId(_ event: CrashlyticsEvent, issueId: String) -> String {
        let firebaseEventId = event.eventId ?? "unknown"
        return "\(canonicalIssueId(issueId))/events/\(firebaseEventId)"
    }

    // Crashlytics quirk: a console `sessionEventKey` looks like `<session>_<eventId>`, so the
    // whole key and the parts after the last / before the first `_` are all tried.
    static func candidateEventIds(forKey key: String) -> [String] {
        let parts = key.split(separator: "_").map(String.init)
        var seen = Set<String>()
        return ([key] + [parts.last, parts.first].compactMap { $0 }).filter { seen.insert($0).inserted }
    }
}
