import Foundation

struct ImpactPayload: Encodable, Sendable, Equatable {
    var since: Date
    var until: Date
    var eventsCount: Int
    var impactedUsersCount: Int
    var appUsersCount: Int?
    var impactedUsersPercentage: Double?

    init(_ impact: IssueImpact) {
        since = impact.since
        until = impact.until
        eventsCount = impact.eventsCount
        impactedUsersCount = impact.impactedUsersCount
        appUsersCount = impact.appUsersCount
        impactedUsersPercentage = impact.impactedUsersPercentage
    }
}

struct ActivityPayload: Encodable, Sendable, Equatable {
    var sampledEvents: Int
    var firstEventAt: String?
    var lastEventAt: String?
    var osSpread: [Spread]
    var deviceSpread: [Spread]
    var versionSpread: [Spread]
    var distinctUsers: Int?

    struct Spread: Encodable, Sendable, Equatable {
        var name: String
        var count: Int

        init(_ spread: SpreadCount) {
            name = spread.name
            count = spread.count
        }
    }

    init(_ activity: IssueActivitySummary) {
        sampledEvents = activity.sampledEvents
        firstEventAt = activity.firstEventAt
        lastEventAt = activity.lastEventAt
        osSpread = activity.osSpread.map(Spread.init)
        deviceSpread = activity.deviceSpread.map(Spread.init)
        versionSpread = activity.versionSpread.map(Spread.init)
        distinctUsers = activity.distinctUsers
    }
}

struct LibraryAttributionPayload: Encodable, Sendable {
    var dominantLibraries: [Entry]
    var blameLibraries: [Entry]

    struct Entry: Encodable, Sendable {
        var library: String
        var events: Int
        var share: Double
        var owner: String?

        init(_ entry: LibraryAttribution.Entry) {
            library = entry.library
            events = entry.events
            share = entry.share
            owner = entry.owner
        }
    }

    init(_ attribution: LibraryAttribution) {
        dominantLibraries = attribution.dominantLibraries.map(Entry.init)
        blameLibraries = attribution.blameLibraries.map(Entry.init)
    }
}
