import Foundation

struct CrashlyticsIssueMapper: Sendable {
    func issue(
        from dto: CrashlyticsDTO.Issue,
        eventsCount: Int? = nil,
        impactedUsersCount: Int? = nil,
        dailyEvents: [DailyEventCount]? = nil
    ) -> CrashIssue {
        CrashIssue(
            providerId: dto.id,
            title: dto.title,
            subtitle: dto.subtitle,
            exceptionType: dto.errorType ?? dto.title ?? "UNKNOWN",
            errorType: dto.errorType,
            state: dto.state,
            signal: dto.signals.first?.signal,
            eventsCount: eventsCount,
            impactedUsersCount: impactedUsersCount,
            firstSeenVersion: dto.firstSeenVersion,
            lastSeenVersion: dto.lastSeenVersion,
            consoleURL: dto.uri,
            dailyEvents: dailyEvents
        )
    }
}
