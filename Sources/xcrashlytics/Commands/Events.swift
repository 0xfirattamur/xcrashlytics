//
//  Events.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 5.06.2026.
//

import ArgumentParser
import Foundation

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "List Firebase Crashlytics events for one or more issues.",
        discussion: """
        Memory and storage fields appear only when Firebase includes them for an event.
        Frame filter flags imply --frames-only for compact agent input.
        """
    )

    @Argument(help: "Canonical issue id, for example FB-ISSUE_ID. Comma-separated ids are accepted.")
    var issueId: String?

    @Option(name: .long, help: "Comma-separated issue ids, for example FB-a,FB-b.")
    var issues: String?

    @Option(name: .long, help: "Output format: text (default), json, or ndjson.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Limit to N events.")
    var limit: Int = 10

    @Option(name: .long, help: "Only include events for this exact Firebase user id.")
    var userId: String?

    @Option(name: .long, help: "Only include events since 7d, 24h, 30m, or all.")
    var since: String?

    @Flag(name: .long, help: "Fetch only the latest event.")
    var latest: Bool = false

    @Flag(name: .long, help: "Only emit frame data for each event.")
    var framesOnly: Bool = false

    @Flag(name: .long, help: "Only emit frames that look app-owned.")
    var appFramesOnly: Bool = false

    @Flag(name: .long, help: "Drop redacted, deduplicated, and known system/SDK frames.")
    var noSystemFrames: Bool = false

    @Flag(name: .long, help: "Prefer frames from Firebase's crashed thread.")
    var crashingThreadOnly: Bool = false

    private static let userIdMinFetchDepth = 50

    func run() async throws {
        try await reportingFailures(jsonOutput: format.isJSON) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(
        _ ctx: CommandContext
    ) async throws -> String {
        let firebase = try ctx.crashlyticsClient()
        let issueIds = try requestedIssueIds()
        let cutoff: Date? = if let since {
            try SinceDuration.cutoffDate(from: since, now: ctx.clock.now())
        } else {
            nil
        }
        let requestedLimit = latest ? 1 : max(1, limit)
        let fetchDepth: Int
        if since != nil {
            fetchDepth = max(requestedLimit, 2_000)
        } else if normalizedUserId != nil {
            fetchDepth = max(requestedLimit, Self.userIdMinFetchDepth)
        } else {
            fetchDepth = requestedLimit
        }
        var issueEvents: [IssueEvents] = []
        var scannedEvents = 0
        var warnings: [CLIWarning] = []
        for issueId in issueIds {
            let events = try await firebase.listEvents(
                issueID: FirebaseIdentifiers.issueId(from: issueId),
                maxEvents: fetchDepth
            )
            scannedEvents += events.count
            if since != nil, events.count >= fetchDepth {
                warnings.append(CLIWarning(
                    code: "SCAN_TRUNCATED",
                    message: "\(issueId): scanned the newest \(fetchDepth) events; older events in the --since window were not checked."))
            }
            let kept = Array(filterBySince(filterByUserId(events), cutoff: cutoff).prefix(requestedLimit))
            issueEvents.append(IssueEvents(issueId: issueId, events: kept))
        }

        let frameOptions = FirebaseFrameFilterOptions(
            appFramesOnly: appFramesOnly,
            noSystemFrames: noSystemFrames,
            crashingThreadOnly: crashingThreadOnly
        )
        let effectiveFramesOnly = framesOnly || appFramesOnly || noSystemFrames || crashingThreadOnly
        let output: String
        switch format {
        case .text:
            output = effectiveFramesOnly
                ? EventsRenderer.framesOnlyText(issueEvents, frameOptions: frameOptions)
                : EventsRenderer.text(issueEvents, frameOptions: frameOptions)
        case .json:
            output = try EventsRenderer.json(
                issueEvents,
                framesOnly: effectiveFramesOnly,
                frameOptions: frameOptions,
                scannedEvents: normalizedUserId == nil ? nil : scannedEvents,
                warnings: warnings
            )
        case .ndjson:
            output = try EventsRenderer.ndjson(issueEvents, framesOnly: effectiveFramesOnly, frameOptions: frameOptions)
        }
        ctx.report(warnings, format: format)
        ctx.console.output(output)
        return output
    }

    private func requestedIssueIds() throws -> [String] {
        let rawValues = [issueId, issues].compactMap { $0 }
        let ids = rawValues
            .flatMap { value in
                value.split(separator: ",").compactMap { String($0).trimmedNonEmpty }
            }
            .map(FirebaseIdentifiers.canonicalIssueId)
        guard !ids.isEmpty else {
            throw ValidationError("provide an issue id argument or --issues FB-a,FB-b.")
        }
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private var normalizedUserId: String? {
        userId?.trimmedNonEmpty
    }

    private func filterBySince(
        _ events: [FirebaseEvent],
        cutoff: Date?
    ) -> [FirebaseEvent] {
        guard let cutoff else { return events }
        return events.filter { event in
            guard let raw = event.eventTime, let date = EventDates.parse(raw) else { return false }
            return date >= cutoff
        }
    }

    private func filterByUserId(_ events: [FirebaseEvent]) -> [FirebaseEvent] {
        guard let normalizedUserId else { return events }
        return events.filter { $0.userId == normalizedUserId }
    }

}
