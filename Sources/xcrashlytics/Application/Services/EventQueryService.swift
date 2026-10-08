import Foundation

struct EventQueryService: Sendable {
    let clients: CrashlyticsClientProvider
    let frameSelectors: ProfileFrameSelector
    let frameSymbolizer: FrameSymbolizer
    let dateProvider: DateProvider

    // MARK: - Public API

    func events(_ request: EventsRequest) async throws -> EventsResult {
        let window = try ReportWindow(since: request.since ?? "all", now: dateProvider.currentDate()).interval
        let client = try clients.client()
        let userId = request.userId?.trimmedNonEmpty
        let plan = EventScanPlan(limit: request.limit, latest: request.latest, userFiltered: userId != nil)

        var scan = try await scanIssues(request.issueIds, userId: userId, plan: plan, window: window, client: client)
        let frameSelector = frameSelectors.selector()
        if !request.dsymPaths.isEmpty {
            let symbolized = frameSymbolizer.symbolicate(
                scan.issueEvents.flatMap(\.events), dsymPaths: request.dsymPaths)
            scan.issueEvents = regroup(symbolized.events, like: scan.issueEvents)
            scan.warnings += symbolized.warnings
        }
        if request.frameFilter.crashingThreadOnly {
            scan.warnings += crashingThreadWarnings(scan.issueEvents)
        }
        return EventsResult(
            request: request,
            issueEvents: scan.issueEvents,
            scan: plan.scansBeyondLimit ? .init(scannedEvents: scan.scannedEvents, depth: plan.depth) : nil,
            warnings: scan.warnings,
            frameSelector: frameSelector)
    }

    // MARK: - Scanning

    private struct IssueScan {
        var issueEvents: [IssueEvents] = []
        var scannedEvents = 0
        var warnings: [CommandWarning] = []
    }

    private func scanIssues(
        _ issueIds: [String],
        userId: String?,
        plan: EventScanPlan,
        window: DateInterval,
        client: CrashlyticsClient
    ) async throws -> IssueScan {
        var scan = IssueScan()
        for issueId in issueIds {
            let fetched = try await client.fetchEvents(
                issueId: CrashlyticsIdFormatter.issueId(from: issueId), limit: plan.depth, interval: window)
            scan.scannedEvents += fetched.count

            let matching = userId.map { id in fetched.filter { $0.userId == id } } ?? fetched
            let kept = Array(matching.prefix(plan.requestedLimit))
            if kept.count < plan.requestedLimit,
               let message = plan.truncationMessage(issueId: issueId, fetchedCount: fetched.count) {
                scan.warnings.append(CommandWarning(code: .scanTruncated, message: message))
            }
            scan.issueEvents.append(IssueEvents(issueId: issueId, events: kept))
        }
        return scan
    }

    // MARK: - Post-processing

    /// The symbolizer returns one flat list.
    private func regroup(_ events: [CrashlyticsEvent], like groups: [IssueEvents]) -> [IssueEvents] {
        var remaining = events[...]
        return groups.map { group in
            defer { remaining = remaining.dropFirst(group.events.count) }
            return IssueEvents(issueId: group.issueId, events: Array(remaining.prefix(group.events.count)))
        }
    }

    private func crashingThreadWarnings(_ issueEvents: [IssueEvents]) -> [CommandWarning] {
        issueEvents.flatMap { group in
            group.events.filter { !$0.hasCrashedThread }.map {
                CrashingThreadWarningFactory.warning(
                    eventId: CrashlyticsIdFormatter.canonicalEventId($0, issueId: group.issueId))
            }
        }
    }
}
