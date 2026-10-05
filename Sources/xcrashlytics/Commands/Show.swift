//
//  Show.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import ArgumentParser
import Foundation

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a single crash by id (XC-<uuid>, FB-<id>) or Firebase console link.",
        discussion: """
        Examples:
          xcrashlytics show FB-3aedb610eee1a41872d991ca62ce8566
          xcrashlytics show FB-3aedb610eee1a41872d991ca62ce8566/events/E1 --format json
          xcrashlytics show XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
          xcrashlytics show 'https://console.firebase.google.com/project/p/crashlytics/app/ios:com.example.app/issues/3aed…'

        Console links are matched to the profile whose bundle id equals the
        link's app; quote the link so the shell leaves `?` and `&` alone.
        """
    )

    @Argument(help: "Crash id (XC-<uuid>, FB-<id>, FB-<id>/events/<event>) or a Firebase console issue link.")
    var id: String

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: OutputFormat = .text

    @Flag(name: .long, help: "Firebase only: only emit frames that look app-owned.")
    var appFramesOnly: Bool = false

    @Flag(name: .long, help: "Firebase only: drop redacted, deduplicated, and known system/SDK frames.")
    var noSystemFrames: Bool = false

    @Flag(name: .long, help: "Firebase only: prefer frames from Firebase's crashed thread.")
    var crashingThreadOnly: Bool = false

    func validate() throws {
        guard format != .ndjson else {
            throw ValidationError("--format ndjson is not supported by this command.")
        }
    }

    func run() async throws {
        try await reportingFailures(jsonOutput: format.isJSON) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(_ ctx: CommandContext) async throws -> String {
        let detail = try await loadCrash(ctx: ctx)
        let output = try render(detail)
        ctx.report(detail.warnings, format: format)
        ctx.console.output(output)
        return output
    }

    private var frameOptions: FirebaseFrameFilterOptions {
        FirebaseFrameFilterOptions(
            appFramesOnly: appFramesOnly,
            noSystemFrames: noSystemFrames,
            crashingThreadOnly: crashingThreadOnly
        )
    }

    private struct Detail {
        var event: CrashEvent
        var issue: CrashIssue?
        var activity: IssueActivitySummary?
        var warnings: [CLIWarning] = []
    }

    private func loadCrash(ctx: CommandContext) async throws -> Detail {
        if FirebaseConsoleLink.looksLikeURL(id) {
            return try await consoleLink(ctx: ctx)
        }
        if id.hasPrefix("XC-") {
            let load = ctx.loadXcodeCrashes(directories: try ctx.xcodeCrashDirectories())
            guard let match = load.crashes.first(where: { $0.event.id == id }) else {
                throw ValidationError("no crash found with id '\(id)'.")
            }
            return Detail(event: match.event, warnings: load.warnings)
        }
        let firebase = try ctx.crashlyticsClient()
        if let ref = FirebaseEventRef(id) {
            return Detail(event: try await firebaseEvent(ref, firebase: firebase))
        }
        if id.hasPrefix("FB-") {
            return try await firebaseIssue(FirebaseIdentifiers.issueId(from: id), firebase: firebase).detail
        }
        throw ValidationError("id must be XC-<uuid>, FB-<id>, or a Firebase console link; got '\(id)'.")
    }

    /// A pasted console link: the app comes from the profile matching the
    /// link's bundle id; `sessionEventKey` selects the event when it resolves.
    private func consoleLink(ctx: CommandContext) async throws -> Detail {
        let link = try FirebaseConsoleLink(id)
        let config = try ConfigFile(fileSystem: ctx.fileSystem).load()
        guard let appId = config.appId(for: link) else {
            throw ValidationError(
                "no profile for bundle id '\(link.bundleId)'. Add one: "
                    + "xcrashlytics init --app-id <APP_ID> --bundle-id \(link.bundleId) --profile <name>")
        }
        let firebase = try ctx.crashlyticsClient(appId: appId)
        var (detail, events) = try await firebaseIssue(link.issueId, firebase: firebase)
        let candidates = link.candidateEventIds
        guard !candidates.isEmpty else { return detail }
        guard let match = events.first(where: { $0.eventId.map(candidates.contains) == true }) else {
            detail.warnings.append(CLIWarning(
                code: "EVENT_NOT_RESOLVED",
                message: "the link's event is not among the newest \(FirebaseEventSampling.limit) events; showing the issue."))
            return detail
        }
        detail.event = FirebaseEventCrashMapper.crashEvent(
            from: match,
            canonicalId: FirebaseIdentifiers.canonicalEventId(match, issueId: link.issueId),
            frameOptions: frameOptions)
        return detail
    }

    private func firebaseEvent(
        _ ref: FirebaseEventRef,
        firebase: CrashlyticsAPI
    ) async throws -> CrashEvent {
        let events = try await firebase.listEvents(issueID: ref.issueId, maxEvents: FirebaseEventSampling.limit)
        guard let dto = events.first(where: { event in
            let eventId = event.eventId
            return eventId == ref.eventId
        }) else {
            throw ValidationError("no Firebase event found with id '\(id)'.")
        }
        return FirebaseEventCrashMapper.crashEvent(from: dto, canonicalId: id, frameOptions: frameOptions)
    }

    /// Issue aggregates plus the newest event's stack; also returns the
    /// sampled events so callers can pick a specific one.
    private func firebaseIssue(
        _ issueId: String,
        firebase: CrashlyticsAPI
    ) async throws -> (detail: Detail, events: [FirebaseEvent]) {
        let issue = try await firebase.getIssueDetail(id: issueId)
        let events = try await firebase.listEvents(issueID: issueId, maxEvents: FirebaseEventSampling.limit)
        let event = CrashEvent(
            id: issue.id,
            providerId: issue.providerId,
            source: .firebase,
            bundleVersion: issue.bundleVersion,
            crashedThreadIndex: 0,
            exception: issue.exception,
            frames: events.first.map { FirebaseEventFrames.frames(from: $0, options: frameOptions) } ?? []
        )
        let activity = events.isEmpty ? nil : IssueActivitySummary(events: events)
        return (Detail(event: event, issue: issue, activity: activity), events)
    }

    private func render(_ detail: Detail) throws -> String {
        if format == .json {
            return try JSONRenderer().renderDetail(
                detail.event, issue: detail.issue, activity: detail.activity, warnings: detail.warnings)
        } else {
            return PlainTextRenderer().renderDetail(detail.event, issue: detail.issue, activity: detail.activity)
        }
    }
}
