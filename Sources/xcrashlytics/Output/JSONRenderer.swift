import Foundation

/// Renders crash data as stable JSON for AI agents and scripts.
struct JSONRenderer: Sendable {
    func renderDetail(
        _ event: CrashEvent,
        issue: CrashIssue? = nil,
        activity: IssueActivitySummary? = nil,
        firebaseEvent: FirebaseEvent? = nil,
        warnings: [CLIWarning] = []
    ) throws -> String {
        try PayloadEncoder.envelope(
            DetailPayload(event: event, issue: issue, activity: activity, firebaseEvent: firebaseEvent),
            warnings: warnings)
    }

    /// The event's fields at the top level, plus issue aggregates, an
    /// `activity` object, and the selected Firebase event's metadata under
    /// the same names `events` uses.
    struct DetailPayload: Encodable {
        let event: CrashEvent
        let issue: CrashIssue?
        let activity: IssueActivitySummary?
        let firebaseEvent: FirebaseEvent?

        enum CodingKeys: String, CodingKey {
            case eventsCount, impactedUsersCount, firstSeenVersion, lastSeenVersion, activity
            case appBuild, processState, deviceOrientation, osOrientation, isJailbroken
            case memoryFreeBytes, memoryUsedBytes, storageFreeBytes, storageUsedBytes, userIdHash
        }

        func encode(to encoder: Encoder) throws {
            try event.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(issue?.eventsCount, forKey: .eventsCount)
            try container.encodeIfPresent(issue?.impactedUsersCount, forKey: .impactedUsersCount)
            try container.encodeIfPresent(issue?.firstSeenVersion, forKey: .firstSeenVersion)
            try container.encodeIfPresent(issue?.lastSeenVersion, forKey: .lastSeenVersion)
            try container.encodeIfPresent(activity, forKey: .activity)
            guard let firebaseEvent else { return }
            try container.encodeIfPresent(firebaseEvent.buildVersion, forKey: .appBuild)
            try container.encodeIfPresent(firebaseEvent.processState, forKey: .processState)
            try container.encodeIfPresent(firebaseEvent.deviceOrientation, forKey: .deviceOrientation)
            try container.encodeIfPresent(firebaseEvent.osOrientation, forKey: .osOrientation)
            try container.encodeIfPresent(firebaseEvent.jailbroken, forKey: .isJailbroken)
            try container.encodeIfPresent(firebaseEvent.memoryFree, forKey: .memoryFreeBytes)
            try container.encodeIfPresent(firebaseEvent.memoryUsed, forKey: .memoryUsedBytes)
            try container.encodeIfPresent(firebaseEvent.storageFree, forKey: .storageFreeBytes)
            try container.encodeIfPresent(firebaseEvent.storageUsed, forKey: .storageUsedBytes)
            try container.encodeIfPresent(firebaseEvent.userId.map(Hashing.sha256Hex), forKey: .userIdHash)
        }
    }

    func renderGroups(_ groups: [CrashGroup], limit: Int?, warnings: [CLIWarning] = []) throws -> String {
        let limited = limit.map { Array(groups.prefix($0)) } ?? groups
        return try PayloadEncoder.envelope(GroupsPayload(groups: limited.map(GroupPayload.init)), warnings: warnings)
    }

    struct GroupsPayload: Encodable {
        let groups: [GroupPayload]
    }

    struct GroupPayload: Encodable {
        let symbol: String
        let module: String?
        let crossSource: Bool
        let totalEvents: Int
        let totalUsers: Int
        let firebase: [CrashIssue]
        let xcode: [XcodeCrash]

        init(_ group: CrashGroup) {
            symbol = group.symbol
            module = group.module
            crossSource = group.isCrossSource
            totalEvents = group.totalEvents
            totalUsers = group.totalUsers
            firebase = group.firebase
            xcode = group.xcode
        }
    }
}
