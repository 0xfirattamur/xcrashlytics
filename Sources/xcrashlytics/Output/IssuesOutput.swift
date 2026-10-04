//
//  IssuesOutput.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation
import XCrashlyticsCore

public struct IssuesPayload: Encodable, Sendable {
    public var query: String?
    public var match: String?
    public var limit: Int
    public var searchLimit: Int
    public var fetchedIssuesCount: Int
    public var matchedIssuesCount: Int
    public var hint: String?
    public var appVersion: String?
    public var sinceVersion: String?
    public var file: String?
    public var symbol: String?
    public var since: String?
    public var domain: String?
    public var userInfoKey: [String]?
    public var eventMetadataSamples: Int?
    public var symbolicationHint: String?
    public var issues: [IssueSummary]
    public var xcodeCrashes: [XcodeIssueSummary]?
    public var relatedGroups: [RelatedIssueGroup]?

    public init(
        query: String?,
        match: String?,
        limit: Int,
        searchLimit: Int,
        fetchedIssuesCount: Int,
        matchedIssuesCount: Int,
        hint: String?,
        appVersion: String?,
        sinceVersion: String?,
        file: String?,
        symbol: String?,
        since: String?,
        domain: String?,
        userInfoKey: [String]?,
        eventMetadataSamples: Int?,
        symbolicationHint: String?,
        issues: [IssueSummary],
        xcodeCrashes: [XcodeIssueSummary]?,
        relatedGroups: [RelatedIssueGroup]?
    ) {
        self.query = query
        self.match = match
        self.limit = limit
        self.searchLimit = searchLimit
        self.fetchedIssuesCount = fetchedIssuesCount
        self.matchedIssuesCount = matchedIssuesCount
        self.hint = hint
        self.appVersion = appVersion
        self.sinceVersion = sinceVersion
        self.file = file
        self.symbol = symbol
        self.since = since
        self.domain = domain
        self.userInfoKey = userInfoKey
        self.eventMetadataSamples = eventMetadataSamples
        self.symbolicationHint = symbolicationHint
        self.issues = issues
        self.xcodeCrashes = xcodeCrashes
        self.relatedGroups = relatedGroups
    }
}

public struct IssueSummary: Encodable, Sendable {
    public var id: String
    public var firebaseIssueId: String
    public var title: String?
    public var subtitle: String?
    public var exceptionType: String?
    public var signal: String?
    public var appVersion: String?
    public var firstSeenVersion: String?
    public var lastSeenVersion: String?
    public var eventsCount: Int?
    public var impactedUsersCount: Int?
    public var module: String?
    public var file: String?
    public var topAppSymbol: String?
    public var dailyEvents: [DailyEventCount]?
    public var dailyEventsSampledCount: Int?
    public var dailyEventsTruncated: Bool?
    public var lastSeenAt: String?

    public init(_ issue: CrashIssue, trend: IssueTrend? = nil, lastSeenAt: String? = nil) {
        let display = DisplaySignature(issue)
        self.id = issue.id
        self.firebaseIssueId = issue.providerId
        self.title = issue.exception.description
        self.subtitle = issue.exception.subtype
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
        self.dailyEvents = trend?.days.isEmpty == false ? trend?.days : nil
        self.dailyEventsSampledCount = trend?.sampledEvents
        self.dailyEventsTruncated = trend?.truncated
        self.lastSeenAt = lastSeenAt
    }
}

/// Per-day counts for one issue, built from a sample of its newest events.
/// `truncated` means the sample did not cover every event, so the oldest
/// sampled day's count is a lower bound.
public struct IssueTrend: Sendable, Equatable {
    public var days: [DailyEventCount]
    public var sampledEvents: Int
    public var totalEvents: Int?
    public var truncated: Bool

    public init(days: [DailyEventCount], sampledEvents: Int, totalEvents: Int?, truncated: Bool) {
        self.days = days
        self.sampledEvents = sampledEvents
        self.totalEvents = totalEvents
        self.truncated = truncated
    }
}

public struct DailyEventCount: Encodable, Sendable, Equatable {
    public var day: String
    public var eventsCount: Int

    public init(day: String, eventsCount: Int) {
        self.day = day
        self.eventsCount = eventsCount
    }
}

public struct XcodeIssueSummary: Encodable, Sendable {
    public var id: String
    public var exceptionType: String
    public var appVersion: String?
    public var deviceModel: String?
    public var topAppSymbol: String?

    public init(_ crash: XcodeCrash) {
        self.id = crash.event.id
        self.exceptionType = crash.event.exception.exceptionType
        self.appVersion = crash.event.bundleVersion
        self.deviceModel = crash.event.deviceModel
        self.topAppSymbol = crash.event.frames.first?.symbol
    }
}

public enum IssuesRenderer {
    public static func text(
        issues: [CrashIssue],
        xcodeCrashes: [XcodeCrash],
        hint: String?,
        symbolicationHint: String?,
        trends: [String: IssueTrend],
        lastSeenAt: [String: String] = [:]
    ) -> String {
        guard !issues.isEmpty || !xcodeCrashes.isEmpty else {
            return [
                "No Firebase issues found.",
                hint.map { "Hint: \($0)" },
                symbolicationHint.map { "Symbolication: \($0)" },
            ].compactMap { $0 }.joined(separator: "\n") + "\n"
        }
        let firebaseText = issues.map { issue in
            let type = issue.exception.exceptionType
            let version = versionDescription(issue)
            let title = issue.exception.description ?? "-"
            let events = issue.eventsCount.map(String.init) ?? "?"
            let users = issue.impactedUsersCount.map(String.init) ?? "?"
            let trendText = trends[issue.id].map { trendDescription($0) } ?? ""
            let seenText = lastSeenAt[issue.id]
                .map { "   last seen \(EventDates.dayString(from: $0) ?? $0)" } ?? ""
            return
                "\(issue.id)   \(type)   \(version)   \(title)   \(events) events / \(users) users\(seenText)\(trendText)"
        }.joined(separator: "\n")
        let xcodeText = xcodeCrashes.map { crash in
            let event = crash.event
            return
                "\(event.id)   \(event.bundleVersion ?? "unknown app")   \(event.exception.exceptionType)"
        }.joined(separator: "\n")
        return [firebaseText, xcodeText].filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
    }

    /// "v6.2.0→v6.16.0" when the seen range spans versions, else the
    /// last-seen version alone.
    private static func versionDescription(_ issue: CrashIssue) -> String {
        guard let last = issue.bundleVersion else { return "-" }
        if let first = issue.firstSeenVersion, first != last {
            return "v\(first)→v\(last)"
        }
        return "v\(last)"
    }

    private static func trendDescription(_ trend: IssueTrend) -> String {
        guard !trend.days.isEmpty else { return "" }
        let days = trend.days.enumerated().map { index, day in
            let bound = trend.truncated && index == 0 ? "≥" : ""
            return "\(day.day):\(bound)\(day.eventsCount)"
        }.joined(separator: ",")
        guard trend.truncated else { return "   \(days)" }
        let coverage = trend.totalEvents
            .map { "sampled newest \(trend.sampledEvents) of \($0) events" }
            ?? "sampled newest \(trend.sampledEvents) events"
        return "   \(days) (\(coverage))"
    }
}
