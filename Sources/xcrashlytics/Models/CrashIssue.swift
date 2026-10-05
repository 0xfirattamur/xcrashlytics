import Foundation

/// A Firebase Crashlytics issue aggregate.
struct CrashIssue: Codable, Sendable, Hashable {
    /// Canonical CLI id: `FB-<issue>`.
    var id: String
    /// Raw Firebase issue id, used for API calls.
    var providerId: String
    var source: CrashSource
    var title: String?
    var subtitle: String?
    var exceptionType: String
    var signal: String?
    var eventsCount: Int?
    var impactedUsersCount: Int?
    var firstSeenVersion: String?
    var lastSeenVersion: String?

    init(
        providerId: String,
        source: CrashSource = .firebase,
        title: String? = nil,
        subtitle: String? = nil,
        exceptionType: String,
        signal: String? = nil,
        eventsCount: Int? = nil,
        impactedUsersCount: Int? = nil,
        firstSeenVersion: String? = nil,
        lastSeenVersion: String? = nil
    ) {
        self.id = FirebaseIdentifiers.canonicalIssueId(providerId)
        self.providerId = providerId
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.exceptionType = exceptionType
        self.signal = signal
        self.eventsCount = eventsCount
        self.impactedUsersCount = impactedUsersCount
        self.firstSeenVersion = firstSeenVersion
        self.lastSeenVersion = lastSeenVersion
    }

    /// Last-seen version, falling back to first-seen.
    var bundleVersion: String? { lastSeenVersion ?? firstSeenVersion }

    /// Issue-level exception summary; title carries the culprit location.
    var exception: ExceptionInfo {
        ExceptionInfo(exceptionType: exceptionType, signal: signal, subtype: subtitle, description: title)
    }
}
