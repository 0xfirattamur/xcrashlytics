import Foundation

struct CrashDetailService: Sendable {
    /// 100 issues per page up to the `--all` cap.
    static let impactMaxPages = IssueSearchPlanner.allSearchLimitCap / 100

    let clients: CrashlyticsClientProvider
    let sources: CrashSourceLoader
    let frameSelectors: ProfileFrameSelector
    let frameSymbolizer: FrameSymbolizer
    let dateProvider: DateProvider

    // MARK: - Public API

    func detail(_ request: CrashDetailRequest) async throws -> CrashDetail {
        let loading = Loading(
            request: request, selector: frameSelectors.selector(), now: dateProvider.currentDate())
        var detail = try await load(loading)
        detail.frameFilter = request.frameFilter
        detail.frameSelector = loading.selector
        if !request.dsymPaths.isEmpty {
            symbolicate(&detail, loading)
        }
        if request.includesVersionRange {
            await attachVersionRange(to: &detail, id: request.id)
        }
        return detail
    }

    // MARK: - Loading context

    private struct Loading {
        var request: CrashDetailRequest
        var selector: FrameSelector
        var now: Date

        var filter: FrameFilter { request.frameFilter }

        var eventWindow: DateInterval { request.impactWindow ?? ReportWindow.maximum(now: now).interval }
    }

    // MARK: - Loading by reference kind

    private func load(_ loading: Loading) async throws -> CrashDetail {
        switch try CrashReference.parse(loading.request.id, expecting: .anyCrash) {
        case let .consoleLink(link):
            return try await consoleLink(link, loading)
        case .xcodeCrash:
            return try xcodeCrash(loading)
        case let .firebaseEvent(reference):
            return try await firebaseEvent(reference, loading)
        case let .firebaseIssue(issueId):
            let client = try clients.client()
            return try await firebaseIssue(issueId, client: client, loading).detail
        }
    }

    private func firebaseEvent(
        _ reference: CrashlyticsEventReference, _ loading: Loading
    ) async throws -> CrashDetail {
        let client = try clients.client()
        var (detail, events) = try await firebaseIssue(reference.issueId, client: client, loading)
        guard let event = try await findEvent(
            matching: reference.matches, in: events, issueId: reference.issueId, client: client, loading)
        else {
            throw InvalidInputError(
                "no Firebase event '\(reference.eventId)' among the newest \(EventSamplingLimits.limit) "
                    + "events of FB-\(reference.issueId).")
        }
        select(event, issueId: reference.issueId, in: &detail, loading)
        return detail
    }

    private func xcodeCrash(_ loading: Loading) throws -> CrashDetail {
        let id = loading.request.id
        let loaded = try sources.xcodeCrashes(directories: loading.request.crashDirectories)
        guard let match = loaded.crashes.first(where: { $0.event.id == id }) else {
            throw InvalidInputError("no crash found with id '\(id)'.")
        }
        var warnings = loaded.warnings
        if loading.filter != .none {
            warnings.append(CommandWarning(
                code: .frameFilterIgnored,
                message: "--app-frames-only, --no-system-frames and --crashing-thread-only apply to Firebase crashes only; "
                    + "\(id) is shown with all its frames."))
        }
        return CrashDetail(event: match.event, warnings: warnings)
    }

    private func consoleLink(_ link: FirebaseConsoleLink, _ loading: Loading) async throws -> CrashDetail {
        let client = try clients.client(for: link)
        var (detail, events) = try await firebaseIssue(link.issueId, client: client, loading)
        guard link.sessionEventKey != nil else { return detail }
        let isLinkEvent: (CrashlyticsEvent) -> Bool = { $0.eventId.map(link.candidateEventIds.contains) == true }
        guard let match = try await findEvent(
            matching: isLinkEvent, in: events, issueId: link.issueId, client: client, loading)
        else {
            detail.warnings.append(CommandWarning(
                code: .eventNotResolved,
                message: "the link's event is not among the newest \(EventSamplingLimits.limit) events; showing the issue."))
            return detail
        }
        select(match, issueId: link.issueId, in: &detail, loading)
        return detail
    }

    /// An event outside a narrower export window is still looked up in the 90-day maximum, since the id names it.
    private func findEvent(
        matching match: (CrashlyticsEvent) -> Bool,
        in events: [CrashlyticsEvent],
        issueId: String,
        client: CrashlyticsClient,
        _ loading: Loading
    ) async throws -> CrashlyticsEvent? {
        if let found = events.first(where: match) { return found }
        let maximum = ReportWindow.maximum(now: loading.now).interval
        guard loading.eventWindow.start > maximum.start else { return nil }
        let wider = try await client.fetchEvents(
            issueId: issueId, limit: EventSamplingLimits.limit, interval: maximum)
        return wider.first(where: match)
    }

    /// The issue's exception fills in when the event has none.
    private func select(
        _ event: CrashlyticsEvent, issueId: String, in detail: inout CrashDetail, _ loading: Loading
    ) {
        let canonicalId = CrashlyticsIdFormatter.canonicalEventId(event, issueId: issueId)
        detail.event = CrashlyticsEventMapper.crashEvent(
            from: event,
            canonicalId: canonicalId,
            fallbackException: detail.issue?.exception,
            frameFilter: loading.filter,
            frameSelector: loading.selector)
        detail.firebaseEvent = event
        // The overview's warning was about the newest event; this event's own replaces it.
        detail.warnings.removeAll { $0.code == CrashingThreadWarningFactory.code.rawValue }
        if loading.filter.crashingThreadOnly, !event.hasCrashedThread {
            detail.warnings.append(CrashingThreadWarningFactory.warning(eventId: canonicalId))
        }
    }

    // MARK: - Firebase issue

    private struct ImpactSection {
        var impact: IssueImpact?
        var dailyEvents: [DailyEventCount]?
        var warnings: [CommandWarning] = []
    }

    private func firebaseIssue(
        _ issueId: String, client: CrashlyticsClient, _ loading: Loading
    ) async throws -> (detail: CrashDetail, events: [CrashlyticsEvent]) {
        let issue = try await client.fetchIssue(id: issueId)
        let impactSection = try await loadImpact(issueId: issueId, client: client, loading)
        let events = try await client.fetchEvents(
            issueId: issueId, limit: EventSamplingLimits.limit, interval: loading.eventWindow)

        var warnings = impactSection.warnings
        if loading.filter.crashingThreadOnly, let latest = events.first, !latest.hasCrashedThread {
            let latestId = CrashlyticsIdFormatter.canonicalEventId(latest, issueId: issueId)
            warnings.append(CrashingThreadWarningFactory.warning(eventId: latestId))
        }
        let detail = CrashDetail(
            event: overviewEvent(issue: issue, latestEvent: events.first, loading),
            issue: issue,
            activity: events.isEmpty ? nil : IssueActivitySummary(events: events),
            latestEvent: events.first,
            impact: impactSection.impact,
            dailyEvents: impactSection.dailyEvents,
            sampledEvents: events,
            warnings: warnings)
        return (detail, events)
    }

    /// Impact and daily counts exist only when the request names an impact window.
    private func loadImpact(
        issueId: String, client: CrashlyticsClient, _ loading: Loading
    ) async throws -> ImpactSection {
        var section = ImpactSection()
        guard let window = loading.request.impactWindow else { return section }
        section.impact = try await client.fetchIssueImpact(
            issueId: issueId, since: window.start, until: window.end, maxPages: Self.impactMaxPages)
        if section.impact == nil {
            section.warnings.append(CommandWarning(
                code: .impactUnavailable,
                message: "FB-\(issueId) is not among the top \(Self.impactMaxPages * 100) issues of the window; "
                    + "event and user totals are omitted."))
        }
        section.dailyEvents = try await client.fetchDailyEventCounts(issueId: issueId, interval: window)
        return section
    }

    /// The issue overview, showing the frames of the newest event when there is one.
    private func overviewEvent(issue: CrashIssue, latestEvent: CrashlyticsEvent?, _ loading: Loading) -> CrashEvent {
        let selector = loading.selector
        return CrashEvent(
            id: issue.id,
            providerId: issue.providerId,
            source: .firebase,
            bundleVersion: issue.bundleVersion,
            crashedThreadIndex: latestEvent.flatMap { selector.chosenThreadIndex(in: $0) } ?? 0,
            exception: issue.exception,
            frames: latestEvent.map { selector.frames(from: $0, filter: loading.filter) } ?? []
        )
    }

    // MARK: - Post-processing

    /// Replaces every event copy held by the detail with its symbolicated twin, then re-selects the frames.
    private func symbolicate(_ detail: inout CrashDetail, _ loading: Loading) {
        guard detail.event.source == .firebase else { return }
        let originalEvents = detail.sampledEvents + [detail.firebaseEvent].compactMap { $0 }
        let result = frameSymbolizer.symbolicate(originalEvents, dsymPaths: loading.request.dsymPaths)
        detail.warnings += result.warnings

        let symbolicatedSamples = Array(result.events.prefix(detail.sampledEvents.count))
        detail.sampledEvents = symbolicatedSamples
        if detail.latestEvent != nil {
            detail.latestEvent = symbolicatedSamples.first
        }
        if detail.firebaseEvent != nil {
            detail.firebaseEvent = result.events.last
        }
        if let frameSource = detail.firebaseEvent ?? detail.latestEvent {
            detail.event.frames = loading.selector.frames(from: frameSource, filter: loading.filter)
        }
    }

    /// Best effort: a failure becomes a warning, not an error.
    private func attachVersionRange(to detail: inout CrashDetail, id: String) async {
        guard detail.event.source == .firebase, let issue = detail.issue else { return }
        do {
            let client = try IssueReportTarget.resolve(id, clients: clients).client
            let window = ReportWindow.maximum(now: dateProvider.currentDate()).interval
            let rows = try await client.fetchBreakdown(
                issueId: issue.providerId, dimension: .version, interval: window)
            detail.versionRange = VersionRange(rows)
        } catch {
            detail.versionRange = nil
            detail.warnings.append(CommandWarning(
                code: .breakdownUnavailable,
                message: "the version report failed (\(FailureMapper.failure(for: error).message)); "
                    + "versionRange is omitted."))
        }
    }
}
