import Foundation

struct CrashIssue: Sendable, Hashable {
    /// Canonical CLI id: `FB-<issue>`.
    var id: String
    var providerId: String
    var source: CrashSource
    var title: String?
    var subtitle: String?
    /// Firebase issues mirror `errorType` here.
    var exceptionType: String
    var errorType: String?
    var state: String?
    var signal: String?
    var eventsCount: Int?
    var impactedUsersCount: Int?
    // Crashlytics quirk: these are the versions of the first and most recent event (chronological),
    // not the bounds of a version range.
    var firstSeenVersion: String?
    var lastSeenVersion: String?
    var consoleURL: String?
    /// Only when the listing asked for daily granularity; days without events are omitted.
    var dailyEvents: [DailyEventCount]?

    init(
        providerId: String,
        source: CrashSource = .firebase,
        title: String? = nil,
        subtitle: String? = nil,
        exceptionType: String,
        errorType: String? = nil,
        state: String? = nil,
        signal: String? = nil,
        eventsCount: Int? = nil,
        impactedUsersCount: Int? = nil,
        firstSeenVersion: String? = nil,
        lastSeenVersion: String? = nil,
        consoleURL: String? = nil,
        dailyEvents: [DailyEventCount]? = nil
    ) {
        self.id = CrashlyticsIdFormatter.canonicalIssueId(providerId)
        self.providerId = providerId
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.exceptionType = exceptionType
        self.errorType = errorType
        self.state = state
        self.signal = signal
        self.eventsCount = eventsCount
        self.impactedUsersCount = impactedUsersCount
        self.firstSeenVersion = firstSeenVersion
        self.lastSeenVersion = lastSeenVersion
        self.consoleURL = consoleURL
        self.dailyEvents = dailyEvents
    }

    var bundleVersion: String? { lastSeenVersion ?? firstSeenVersion }

    var exception: ExceptionDescriptor {
        ExceptionDescriptor(exceptionType: exceptionType, signal: signal, subtype: subtitle, description: title)
    }
}
