import Foundation

struct IssueSummary: Encodable, Sendable {
    var id: String
    var firebaseIssueId: String
    var title: String?
    var subtitle: String?
    var source: String
    var errorType: String?
    var exceptionType: String?
    var signal: String?
    var appVersion: String?
    /// Version of the issue's first event (chronological, not a range bound).
    var firstSeenVersion: String?
    /// Version of the issue's most recent event; can be lower than `firstSeenVersion`.
    var lastSeenVersion: String?
    var eventsCount: Int?
    var impactedUsersCount: Int?
    var module: String?
    var file: String?
    var topAppSymbol: String?
    var dailyEvents: [DailyEventCountPayload]?
    var dailyEventsSampledCount: Int?
    var dailyEventsTruncated: Bool?
    var lastSeenAt: String?

    init(_ issue: CrashIssue, lastSeenAt: String? = nil) {
        let display = IssueDisplaySignature(issue)
        self.id = issue.id
        self.firebaseIssueId = issue.providerId
        self.title = issue.exception.description
        self.subtitle = issue.exception.subtype
        self.source = issue.source.rawValue
        self.errorType = issue.errorType
        self.exceptionType = issue.exception.exceptionType
        self.signal = issue.exception.signal
        self.appVersion = issue.bundleVersion
        self.firstSeenVersion = issue.firstSeenVersion
        self.lastSeenVersion = issue.lastSeenVersion
        self.eventsCount = issue.eventsCount
        self.impactedUsersCount = issue.impactedUsersCount
        self.module = display?.module
        self.file = display?.file
        self.topAppSymbol = display?.symbol
        let days = issue.dailyEvents
        self.dailyEvents = days?.isEmpty == false ? days?.map(DailyEventCountPayload.init) : nil
        self.dailyEventsSampledCount = days.map { $0.reduce(0) { $0 + $1.eventsCount } }
        self.dailyEventsTruncated = days == nil ? nil : false
        self.lastSeenAt = lastSeenAt
    }
}
