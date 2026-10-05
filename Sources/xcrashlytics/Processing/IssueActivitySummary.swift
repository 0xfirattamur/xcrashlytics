import Foundation

/// One name's share of a sampled spread (OS versions, device models).
struct SpreadCount: Encodable, Sendable, Equatable {
    var name: String
    var count: Int

}

/// Aggregates a sample of an issue's newest events into the summary header
/// `show` prints: date range, OS/device spread, distinct users. Everything
/// here describes the sample, not the issue's full history.
struct IssueActivitySummary: Encodable, Sendable, Equatable {
    var sampledEvents: Int
    var firstEventAt: String?
    var lastEventAt: String?
    var osSpread: [SpreadCount]
    var deviceSpread: [SpreadCount]
    var distinctUsers: Int?

    init(
        sampledEvents: Int,
        firstEventAt: String?,
        lastEventAt: String?,
        osSpread: [SpreadCount],
        deviceSpread: [SpreadCount],
        distinctUsers: Int?
    ) {
        self.sampledEvents = sampledEvents
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
        self.osSpread = osSpread
        self.deviceSpread = deviceSpread
        self.distinctUsers = distinctUsers
    }

    init(events: [FirebaseEvent]) {
        let times = events.compactMap(\.eventTime).sorted()
        let users = Set(events.compactMap { $0.userId })
        self.init(
            sampledEvents: events.count,
            firstEventAt: times.first,
            lastEventAt: times.last,
            osSpread: Self.spread(events.compactMap { event in
                event.osVersion.map { "iOS \($0)" }
            }),
            deviceSpread: Self.spread(events.compactMap { $0.deviceModel }),
            distinctUsers: users.isEmpty ? nil : users.count
        )
    }

    private static func spread(_ values: [String]) -> [SpreadCount] {
        Dictionary(grouping: values, by: { $0 })
            .map { SpreadCount(name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }
    }
}
