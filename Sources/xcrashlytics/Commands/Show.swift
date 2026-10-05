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

    @Option(
        name: .customLong("crash-directory"),
        help: "XC- ids: Xcode crash directory to scan instead of the profile's Organizer directories. Repeatable.")
    var crashDirectories: [String] = []

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
        /// The selected Firebase event, when one was resolved.
        var firebaseEvent: FirebaseEvent?
        var warnings: [CLIWarning] = []
    }

    private func loadCrash(ctx: CommandContext) async throws -> Detail {
        if FirebaseConsoleLink.looksLikeURL(id) {
            return try await consoleLink(ctx: ctx)
        }
        if id.hasPrefix("XC-") {
            let load = try ctx.loadXcodeCrashes(directories: crashDirectories)
            guard let match = load.crashes.first(where: { $0.event.id == id }) else {
                throw ValidationError("no crash found with id '\(id)'.")
            }
            return Detail(event: match.event, warnings: load.warnings)
        }
        let firebase = try ctx.crashlyticsClient()
        if let ref = FirebaseEventRef(id) {
            var (detail, events) = try await firebaseIssue(ref.issueId, firebase: firebase)
            guard let event = events.first(where: ref.matches) else {
                throw ValidationError(
                    "no Firebase event '\(ref.eventId)' among the newest \(FirebaseEventSampling.limit) events of FB-\(ref.issueId).")
            }
            select(event, issueId: ref.issueId, in: &detail)
            return detail
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
        guard link.sessionEventKey != nil else { return detail }
        guard let match = events.first(where: { $0.eventId.map(link.candidateEventIds.contains) == true }) else {
            detail.warnings.append(CLIWarning(
                code: "EVENT_NOT_RESOLVED",
                message: "the link's event is not among the newest \(FirebaseEventSampling.limit) events; showing the issue."))
            return detail
        }
        select(match, issueId: link.issueId, in: &detail)
        return detail
    }

    /// Shows one sampled event instead of the issue overview. Issue aggregates
    /// stay, and the issue's exception fills in when the event has none.
    private func select(_ event: FirebaseEvent, issueId: String, in detail: inout Detail) {
        detail.event = FirebaseEventCrashMapper.crashEvent(
            from: event,
            canonicalId: FirebaseIdentifiers.canonicalEventId(event, issueId: issueId),
            fallbackException: detail.issue?.exception,
            frameOptions: frameOptions)
        detail.firebaseEvent = event
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
                detail.event, issue: detail.issue, activity: detail.activity,
                firebaseEvent: detail.firebaseEvent, warnings: detail.warnings)
        } else {
            return PlainTextRenderer().renderDetail(
                detail.event, issue: detail.issue, activity: detail.activity, firebaseEvent: detail.firebaseEvent)
        }
    }
}
