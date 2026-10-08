import Foundation

/// A Crashlytics issue link copied from the Firebase console:
/// `https://console.firebase.google.com/project/<project>/crashlytics/app/<platform>:<bundle>/issues/<issue>`
/// plus an optional `?sessionEventKey=<key>`.
/// It carries the bundle id, not the Firebase app id, so callers map it to a configured profile.
struct FirebaseConsoleLink: Sendable, Equatable {
    var projectId: String
    var platform: String
    var bundleId: String
    var issueId: String
    var sessionEventKey: String?

    static let host = "console.firebase.google.com"

    static func looksLikeURL(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("https://") || lowered.hasPrefix("http://")
    }

    // Privacy: query values other than `sessionEventKey` are never echoed in errors.
    init(_ value: String) throws {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host?.lowercased() == Self.host
        else {
            throw InvalidInputError("only https://\(Self.host) Crashlytics links are supported.")
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 7,
              parts[0] == "project", parts[2] == "crashlytics", parts[3] == "app", parts[5] == "issues",
              let colon = parts[4].firstIndex(of: ":")
        else {
            throw InvalidInputError(
                "not a Crashlytics issue link; expected "
                    + "…/project/<project>/crashlytics/app/<platform>:<bundle>/issues/<issue>.")
        }
        let platform = String(parts[4][..<colon])
        let bundleId = String(parts[4][parts[4].index(after: colon)...])
        guard !parts[1].isEmpty, !platform.isEmpty, !bundleId.isEmpty, !parts[6].isEmpty else {
            throw InvalidInputError("Crashlytics link is missing its project, app, or issue.")
        }
        self.projectId = parts[1]
        self.platform = platform
        self.bundleId = bundleId
        self.issueId = parts[6]
        self.sessionEventKey = components.queryItems?
            .first(where: { $0.name == "sessionEventKey" })?.value?.trimmedNonEmpty
    }

    var candidateEventIds: [String] {
        sessionEventKey.map(CrashlyticsIdFormatter.candidateEventIds(forKey:)) ?? []
    }
}
