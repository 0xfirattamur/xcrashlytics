//
//  IssuesOutput.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

struct IssuesPayload: Encodable, Sendable {
    var query: String?
    var match: String?
    var limit: Int
    var searchLimit: Int
    var fetchedIssuesCount: Int
    var matchedIssuesCount: Int
    var hint: String?
    var appVersion: String?
    var sinceVersion: String?
    var file: String?
    var symbol: String?
    var since: String?
    var domain: String?
    var userInfoKey: [String]?
    var eventMetadataSamples: Int?
    var symbolicationHint: String?
    var issues: [IssueSummary]
    var xcodeCrashes: [XcodeIssueSummary]?
    var relatedGroups: [RelatedIssueGroup]?

}

struct IssueSummary: Encodable, Sendable {
    var id: String
    var firebaseIssueId: String
    var title: String?
    var subtitle: String?
    var exceptionType: String?
    var signal: String?
    var appVersion: String?
    var firstSeenVersion: String?
    var lastSeenVersion: String?
    var eventsCount: Int?
    var impactedUsersCount: Int?
    var module: String?
    var file: String?
    var topAppSymbol: String?
    var dailyEvents: [DailyEventCount]?
    var dailyEventsSampledCount: Int?
    var dailyEventsTruncated: Bool?
    var lastSeenAt: String?

    init(_ issue: CrashIssue, trend: IssueTrend? = nil, lastSeenAt: String? = nil) {
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
struct IssueTrend: Sendable, Equatable {
    var days: [DailyEventCount]
    var sampledEvents: Int
    var totalEvents: Int?
    var truncated: Bool

}

struct DailyEventCount: Encodable, Sendable, Equatable {
    var day: String
    var eventsCount: Int

}

struct XcodeIssueSummary: Encodable, Sendable {
    var id: String
    var exceptionType: String
    var appVersion: String?
    var deviceModel: String?
    var topAppSymbol: String?

    init(_ crash: XcodeCrash) {
        self.id = crash.event.id
        self.exceptionType = crash.event.exception.exceptionType
        self.appVersion = crash.event.bundleVersion
        self.deviceModel = crash.event.deviceModel
        self.topAppSymbol = crash.event.frames.first?.symbol
    }
}

enum IssuesRenderer {
    static func text(
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
