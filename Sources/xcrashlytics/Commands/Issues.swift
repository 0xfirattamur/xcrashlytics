//
//  Issues.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 5.06.2026.
//

import ArgumentParser
import Foundation
import XCrashlyticsCore

struct IssuesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "issues",
        abstract: "List Firebase Crashlytics issues.",
        discussion: """
            Results follow Firebase topIssues impact order. Bare issues fetches --limit issues.
            Queries and filters fetch a wider search window by default, then show the first --limit matches.
            """
    )

    @Argument(help: "Optional title/subtitle/module/file/symbol query.")
    var query: String?

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Limit displayed issues.")
    var limit: Int = 20

    @Option(name: .long, help: "Number of Firebase issues to fetch before filtering.")
    var searchLimit: Int?

    @Flag(name: .long, help: "Search up to 2000 Firebase issues before filtering.")
    var all: Bool = false

    @Option(
        name: .long,
        help: "Case-insensitive substring filter for title/subtitle/module/file/symbol.")
    var match: String?

    @Option(
        name: .long,
        help: "Filter by Firebase error type, for example FATAL, NON_FATAL, EXC_BAD_ACCESS.")
    var type: String?

    @Option(name: .long, help: "Only include issues with at least N events.")
    var minEvents: Int?

    @Option(
        name: .long,
        help: "Only include issues first- or last-seen in this exact app version.")
    var appVersion: String?

    @Option(
        name: .long,
        help: "Only include issues whose last-seen version is greater than or equal to this version.")
    var sinceVersion: String?

    @Option(
        name: .long, help: "Only include issues whose parsed top file exactly matches this value.")
    var file: String?

    @Option(
        name: .long, help: "Only include issues whose parsed top symbol exactly matches this value."
    )
    var symbol: String?

    @Option(
        name: .long,
        help:
            "Only include issues whose latest sample event is since a duration like 24h, 7d, 30m, or all."
    )
    var since: String?

    @Flag(name: .long, help: "Include per-day event counts for displayed issues.")
    var byDay: Bool = false

    @Option(name: .long, help: "Maximum events to sample per issue when building --by-day trends.")
    var eventsPerIssue: Int = 100

    @Option(
        name: .long,
        help: "Only include issues with a sampled event for this exact Firebase user id.")
    var userId: String?

    @Option(
        name: .long,
        help: "Only include issues whose latest event metadata contains this NSError/domain string."
    )
    var domain: String?

    @Option(
        name: .long, parsing: .upToNextOption,
        help: "Filter latest event userInfo by key or key=value. Repeatable.")
    var userInfoKey: [String] = []

    @Flag(name: .long, help: "Include local crash reports downloaded by the Xcode Organizer.")
    var xcode: Bool = false


    @Option(
        name: .customLong("crash-directory"), help: "Xcode crash directory to scan. Repeatable.")
    var crashDirectories: [String] = []

    var issueFilter: IssueFilter {
        IssueFilter(criteria: IssueSearchCriteria(
            query: query, match: match, type: type, minEvents: minEvents,
            appVersion: appVersion, sinceVersion: sinceVersion, file: file,
            symbol: symbol, domain: domain, userInfoKey: userInfoKey, userId: userId))
    }

    func run() async throws {
        try await reportingFailures(jsonOutput: format.isJSON) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(
        _ ctx: CommandContext,
        crashDirectories overrideDirectories: [String]? = nil
    ) async throws -> String {
        let firebase = try ctx.firebaseClient()
        let filter = issueFilter
        let outputLimit = max(1, limit)
        let fetchLimit = IssueSearchPlanner.resolvedSearchLimit(
            outputLimit: outputLimit, explicit: searchLimit, all: all,
            hasCriteria: filter.hasSearchCriteria)
        let fetchedIssues = try await firebase.listIssues(maxIssues: fetchLimit)
        var warnings: [CLIWarning] = []
        if all, fetchedIssues.count >= IssueSearchPlanner.allSearchLimitCap {
            warnings.append(CLIWarning(
                code: "SEARCH_TRUNCATED",
                message: "--all is capped at \(IssueSearchPlanner.allSearchLimitCap) issues; results may be truncated."))
        }
        var issues = fetchedIssues.filter(filter.matchesIssueFields)
        var eventMetadataSamples = 0
        if filter.requiresEventMetadataSearch {
            let filtered = try await filterByEventMetadata(issues, firebase: firebase, filter: filter)
            issues = filtered.issues
            eventMetadataSamples = filtered.samples
        }
        if let since {
            let cutoff = try SinceDuration.cutoffDate(from: since, now: ctx.clock.now())
            issues = try await filterByLatestEventSince(issues, firebase: firebase, cutoff: cutoff)
        }
        let xcodeLoad = try loadXcodeCrashes(ctx: ctx, overrideDirectories: overrideDirectories)
        warnings += xcodeLoad.warnings
        let xcodeCrashes = xcodeLoad.crashes
            .filter { crash in
                guard filter.matchesXcodeEvent(crash.event) else { return false }
                guard let since else { return true }
                guard since != "all",
                      let cutoff = try? SinceDuration.cutoffDate(from: since, now: ctx.clock.now())
                else { return true }
                return crash.event.timestamp.map { $0 >= cutoff } ?? false
            }

        let output: String
        let hint = IssueSearchPlanner.emptyResultHint(
            hasCriteria: filter.hasSearchCriteria,
            fetchedCount: fetchedIssues.count,
            fetchLimit: fetchLimit,
            matchedCount: issues.count
        )
        let displayedIssues = Array(issues.prefix(outputLimit))
        let activity = try await loadActivity(
            displayedIssues,
            firebase: firebase,
            now: ctx.clock.now()
        )
        let symbolicationHint = (displayedIssues.isEmpty && xcode && !xcodeCrashes.isEmpty)
            ? SymbolicationAdvisor.hint(for: xcodeCrashes) : nil
        switch format {
        case .text:
            output = IssuesRenderer.text(
                issues: displayedIssues,
                xcodeCrashes: xcodeCrashes,
                hint: hint,
                symbolicationHint: symbolicationHint,
                trends: activity.trends,
                lastSeenAt: activity.lastSeenAt
            )
        case .json:
            let payload = IssuesPayload(
                query: query,
                match: match,
                limit: outputLimit,
                searchLimit: fetchLimit,
                fetchedIssuesCount: fetchedIssues.count,
                matchedIssuesCount: issues.count,
                hint: hint,
                appVersion: appVersion,
                sinceVersion: sinceVersion,
                file: file,
                symbol: symbol,
                since: since,
                domain: domain,
                userInfoKey: userInfoKey.nilIfEmpty,
                eventMetadataSamples: eventMetadataSamples > 0 ? eventMetadataSamples : nil,
                symbolicationHint: symbolicationHint,
                issues: displayedIssues.map {
                    IssueSummary($0, trend: activity.trends[$0.id], lastSeenAt: activity.lastSeenAt[$0.id])
                },
                xcodeCrashes: xcode ? xcodeCrashes.map(XcodeIssueSummary.init) : nil,
                relatedGroups: RelatedIssueGroups.build(firebase: displayedIssues, xcode: xcodeCrashes)
                    .nilIfEmpty
            )
            output = try PayloadEncoder.envelope(payload, warnings: warnings)
        case .ndjson:
            output = try PayloadEncoder.ndjson(displayedIssues.map {
                IssueSummary($0, trend: activity.trends[$0.id], lastSeenAt: activity.lastSeenAt[$0.id])
            })
        }
        ctx.report(warnings, format: format)
        ctx.console.output(output)
        return output
    }

    private func loadXcodeCrashes(
        ctx: CommandContext,
        overrideDirectories: [String]?
    ) throws -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        guard xcode else { return ([], []) }
        let directories =
            try overrideDirectories
            ?? (crashDirectories.isEmpty ? ctx.xcodeCrashDirectories() : crashDirectories)
        return ctx.loadXcodeCrashes(directories: directories)
    }

}

extension IssuesCommand {
    func filterByEventMetadata(
        _ issues: [CrashIssue],
        firebase: FirebaseCrashlyticsClient,
        filter: IssueFilter
    ) async throws -> (issues: [CrashIssue], samples: Int) {
        let maxEvents = filter.normalizedUserId == nil ? 1 : max(1, eventsPerIssue)
        let sampled = try await IssueEventSampler(
            firebase: firebase, eventsPerIssue: maxEvents
        ).sample(issues: issues)
        var filtered: [CrashIssue] = []
        var samples = 0
        for sample in sampled where !sample.events.isEmpty {
            samples += sample.events.count
            if sample.events.contains(where: { filter.matchesEventMetadata(issue: sample.issue, event: $0) }) {
                filtered.append(sample.issue)
            }
        }
        return (filtered, samples)
    }

    func filterByLatestEventSince(
        _ issues: [CrashIssue],
        firebase: FirebaseCrashlyticsClient,
        cutoff: Date?
    ) async throws -> [CrashIssue] {
        guard cutoff != nil else { return issues }
        let sampled = try await IssueEventSampler(
            firebase: firebase, eventsPerIssue: 1
        ).sample(issues: issues)
        return sampled.compactMap { sample in
            guard let latest = sample.events.first,
                EventDates.isIncluded(event: latest, onOrAfter: cutoff)
            else { return nil }
            return sample.issue
        }
    }

    struct IssueActivity {
        var trends: [String: IssueTrend] = [:]
        var lastSeenAt: [String: String] = [:]
    }

    /// One sampling pass per displayed issue: the newest event's time always
    /// (for last-seen), per-day counts only when --by-day asked for them.
    func loadActivity(
        _ issues: [CrashIssue],
        firebase: FirebaseCrashlyticsClient,
        now: Date
    ) async throws -> IssueActivity {
        guard !issues.isEmpty else { return IssueActivity() }
        let cutoff =
            try since.map { try SinceDuration.cutoffDate(from: $0, now: now) } ?? nil
        let cap = byDay ? max(1, eventsPerIssue) : 1
        let sampled = try await IssueEventSampler(
            firebase: firebase, eventsPerIssue: cap
        ).sample(issues: issues)
        var activity = IssueActivity()
        for sample in sampled {
            if let latest = sample.events.first?.eventTime {
                activity.lastSeenAt[sample.issue.id] = latest
            }
            guard byDay else { continue }
            var counts: [String: Int] = [:]
            for event in sample.events
            where EventDates.isIncluded(event: event, onOrAfter: cutoff) {
                guard let day = EventDates.dayString(from: event.eventTime) else { continue }
                counts[day, default: 0] += 1
            }
            let sampledCount = sample.events.count
            let total = sample.issue.eventsCount
            // Without a total, a sample that filled the cap may still have missed events.
            let truncated = total.map { sampledCount < $0 } ?? (sampledCount >= cap)
            activity.trends[sample.issue.id] = IssueTrend(
                days: counts
                    .map { DailyEventCount(day: $0.key, eventsCount: $0.value) }
                    .sorted { $0.day < $1.day },
                sampledEvents: sampledCount,
                totalEvents: total,
                truncated: truncated
            )
        }
        return activity
    }

}
