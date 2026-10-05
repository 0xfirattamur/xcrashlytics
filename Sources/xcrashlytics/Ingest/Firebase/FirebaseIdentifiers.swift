import Foundation

enum FirebaseIdentifiers {
    static func issueId(from canonical: String) -> String {
        canonical.hasPrefix("FB-") ? String(canonical.dropFirst(3)) : canonical
    }

    static func canonicalIssueId(_ issueId: String) -> String {
        issueId.hasPrefix("FB-") ? issueId : "FB-\(issueId)"
    }

    static func canonicalEventId(_ event: FirebaseEvent, issueId: String) -> String {
        let firebaseEventId = event.eventId ?? "unknown"
        return "\(canonicalIssueId(issueId))/events/\(firebaseEventId)"
    }
}

struct FirebaseEventRef: Sendable, Equatable {
    var issueId: String
    var eventId: String

    init?(_ id: String) {
        guard id.hasPrefix("FB-"), let range = id.range(of: "/events/") else {
            return nil
        }
        self.issueId = String(id[id.index(id.startIndex, offsetBy: 3)..<range.lowerBound])
        self.eventId = String(id[range.upperBound...])
        guard !issueId.isEmpty, !eventId.isEmpty else { return nil }
    }
}

/// A Crashlytics issue link copied from the Firebase console:
/// `https://console.firebase.google.com/project/<project>/crashlytics/app/<platform>:<bundle>/issues/<issue>?sessionEventKey=<key>`.
///
/// The link carries the bundle id, not the Firebase app id — callers map the
/// bundle id to a configured profile to know which app to query.
struct FirebaseConsoleLink: Sendable, Equatable {
    var projectId: String
    var platform: String
    var bundleId: String
    var issueId: String
    var sessionEventKey: String?

    static let host = "console.firebase.google.com"

    /// True for anything shaped like a URL; such input must parse or be rejected.
    static func looksLikeURL(_ value: String) -> Bool {
        value.hasPrefix("https://") || value.hasPrefix("http://")
    }

    /// Parses a console link, or throws `FirebaseError.invalidRequest` with the
    /// reason. Query values other than `sessionEventKey` are never echoed back.
    init(_ value: String) throws {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host?.lowercased() == Self.host
        else {
            throw FirebaseError.invalidRequest("only https://\(Self.host) Crashlytics links are supported.")
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 7,
              parts[0] == "project", parts[2] == "crashlytics", parts[3] == "app", parts[5] == "issues",
              let colon = parts[4].firstIndex(of: ":")
        else {
            throw FirebaseError.invalidRequest(
                "not a Crashlytics issue link; expected …/project/<project>/crashlytics/app/<platform>:<bundle>/issues/<issue>.")
        }
        let platform = String(parts[4][..<colon])
        let bundleId = String(parts[4][parts[4].index(after: colon)...])
        guard !parts[1].isEmpty, !platform.isEmpty, !bundleId.isEmpty, !parts[6].isEmpty else {
            throw FirebaseError.invalidRequest("Crashlytics link is missing its project, app, or issue.")
        }
        self.projectId = parts[1]
        self.platform = platform
        self.bundleId = bundleId
        self.issueId = parts[6]
        self.sessionEventKey = components.queryItems?
            .first(where: { $0.name == "sessionEventKey" })?.value?.trimmedNonEmpty
    }

    /// Canonical `FB-<issue>` id.
    var canonicalIssueId: String { FirebaseIdentifiers.canonicalIssueId(issueId) }

    /// Event ids this link's `sessionEventKey` may correspond to. The console
    /// key's relation to the API event id is undocumented, so both the whole
    /// key and its part before `_` are tried.
    var candidateEventIds: [String] {
        guard let key = sessionEventKey else { return [] }
        let prefix = key.split(separator: "_").first.map(String.init)
        return [key] + (prefix.map { $0 == key ? [] : [$0] } ?? [])
    }
}

extension Config {
    /// App id to query for a console link: the profile whose bundle id matches,
    /// else the active app when its bundle id is unknown. `nil` means the link
    /// points at an app this config does not know — querying the active app
    /// would silently hit the wrong project.
    func appId(for link: FirebaseConsoleLink) -> String? {
        let match = profiles
            .sorted { $0.key < $1.key }
            .first {
                $0.value.bundleId?.caseInsensitiveCompare(link.bundleId) == .orderedSame
                    && $0.value.appId.split(separator: ":").dropFirst(2).first.map(String.init) == link.platform
            }
        if let match { return match.value.appId }
        return resolvedBundleId == nil ? resolvedAppId : nil
    }
}
