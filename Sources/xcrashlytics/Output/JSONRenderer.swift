//
//  JSONRenderer.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Renders crash data as stable JSON for AI agents and scripts.
struct JSONRenderer: Sendable {
    func renderDetail(
        _ event: CrashEvent,
        issue: CrashIssue? = nil,
        activity: IssueActivitySummary? = nil,
        warnings: [CLIWarning] = []
    ) throws -> String {
        try PayloadEncoder.envelope(DetailPayload(event: event, issue: issue, activity: activity), warnings: warnings)
    }

    /// The event's fields at the top level, plus issue aggregates and an
    /// `activity` object when present.
    struct DetailPayload: Encodable {
        let event: CrashEvent
        let issue: CrashIssue?
        let activity: IssueActivitySummary?

        enum CodingKeys: String, CodingKey {
            case eventsCount, impactedUsersCount, firstSeenVersion, lastSeenVersion, activity
        }

        func encode(to encoder: Encoder) throws {
            try event.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(issue?.eventsCount, forKey: .eventsCount)
            try container.encodeIfPresent(issue?.impactedUsersCount, forKey: .impactedUsersCount)
            try container.encodeIfPresent(issue?.firstSeenVersion, forKey: .firstSeenVersion)
            try container.encodeIfPresent(issue?.lastSeenVersion, forKey: .lastSeenVersion)
            try container.encodeIfPresent(activity, forKey: .activity)
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
