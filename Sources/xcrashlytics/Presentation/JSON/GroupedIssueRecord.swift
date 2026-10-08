struct GroupedIssueRecord: Encodable, Sendable {
    let id: String
    let providerId: String
    let source: String
    let title: String?
    let subtitle: String?
    let exceptionType: String
    let errorType: String?
    let state: String?
    let signal: String?
    let eventsCount: Int?
    let impactedUsersCount: Int?
    let firstSeenVersion: String?
    let lastSeenVersion: String?
    let consoleURL: String?
    let dailyEvents: [DailyEventCountPayload]?

    init(_ issue: CrashIssue) {
        id = issue.id
        providerId = issue.providerId
        source = issue.source.rawValue
        title = issue.title
        subtitle = issue.subtitle
        exceptionType = issue.exceptionType
        errorType = issue.errorType
        state = issue.state
        signal = issue.signal
        eventsCount = issue.eventsCount
        impactedUsersCount = issue.impactedUsersCount
        firstSeenVersion = issue.firstSeenVersion
        lastSeenVersion = issue.lastSeenVersion
        consoleURL = issue.consoleURL
        dailyEvents = issue.dailyEvents?.map(DailyEventCountPayload.init)
    }
}
