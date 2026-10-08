import Foundation

/// The `show` header over a sample of an issue's newest events; it describes the sample,
/// not the issue's full history.
struct IssueActivitySummary: Sendable, Equatable {
    var sampledEvents: Int
    var firstEventAt: String?
    var lastEventAt: String?
    var osSpread: [SpreadCount]
    var deviceSpread: [SpreadCount]
    var versionSpread: [SpreadCount]
    var distinctUsers: Int?

    init(
        sampledEvents: Int,
        firstEventAt: String?,
        lastEventAt: String?,
        osSpread: [SpreadCount],
        deviceSpread: [SpreadCount],
        versionSpread: [SpreadCount] = [],
        distinctUsers: Int?
    ) {
        self.sampledEvents = sampledEvents
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
        self.osSpread = osSpread
        self.deviceSpread = deviceSpread
        self.versionSpread = versionSpread
        self.distinctUsers = distinctUsers
    }

    init(events: [CrashlyticsEvent]) {
        let times = events.compactMap(\.eventTime)
            .compactMap { raw in EventTimestampParser.parse(raw).map { (date: $0, raw: raw) } }
            .sorted { $0.date < $1.date }
        let users = Set(events.compactMap { $0.userId })
        self.init(
            sampledEvents: events.count,
            firstEventAt: times.first?.raw,
            lastEventAt: times.last?.raw,
            osSpread: Self.spread(events.compactMap { event in
                event.osVersion.map { PlatformLabelFormatter.os($0, platform: event.platform) }
            }),
            deviceSpread: Self.spread(events.compactMap { $0.deviceModel }),
            versionSpread: Self.spread(events.compactMap { $0.displayVersion }),
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
