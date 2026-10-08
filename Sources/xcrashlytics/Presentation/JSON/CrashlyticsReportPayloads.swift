struct DailyEventCountPayload: Encodable, Sendable, Equatable {
    var day: String
    var eventsCount: Int

    init(_ count: DailyEventCount) {
        day = count.day
        eventsCount = count.eventsCount
    }
}

struct VersionRangePayload: Encodable, Sendable, Equatable {
    var min: String
    var max: String

    init(_ range: VersionRange) {
        min = range.min
        max = range.max
    }
}

struct BreakdownRowPayload: Encodable, Sendable, Equatable {
    var dimension: String
    var name: String
    var displayVersion: String?
    var buildVersion: String?
    var os: String?
    var osVersion: String?
    var manufacturer: String?
    var model: String?
    var marketingName: String?
    var eventsCount: Int
    var impactedUsersCount: Int
    var eventsShare: Double?
    var sessionsCount: Int?
    var versionUsersCount: Int?
    var impactedUsersPercentage: Double?
    var usersCount: Int?
    var totalSessionsCount: Int?
    var crashFreeUsersPercentage: Double?

    init(_ row: BreakdownRow) {
        dimension = row.dimension.rawValue
        name = row.name
        displayVersion = row.displayVersion
        buildVersion = row.buildVersion
        os = row.os
        osVersion = row.osVersion
        manufacturer = row.manufacturer
        model = row.model
        marketingName = row.marketingName
        eventsCount = row.eventsCount
        impactedUsersCount = row.impactedUsersCount
        eventsShare = row.eventsShare
        sessionsCount = row.sessionsCount
        versionUsersCount = row.versionUsersCount
        impactedUsersPercentage = row.impactedUsersPercentage
        usersCount = row.usersCount
        totalSessionsCount = row.totalSessionsCount
        crashFreeUsersPercentage = row.crashFreeUsersPercentage
    }
}

struct RelatedIssueGroupPayload: Encodable, Sendable {
    var issueIds: [String]
    var reason: String

    init(_ group: RelatedIssueGroup) {
        issueIds = group.issueIds
        reason = group.reason
    }
}

struct WarningPayload: Encodable, Sendable, Equatable {
    var code: String
    var message: String
    var path: String?

    init(_ warning: CommandWarning) {
        code = warning.code
        message = warning.message
        path = warning.path
    }
}
