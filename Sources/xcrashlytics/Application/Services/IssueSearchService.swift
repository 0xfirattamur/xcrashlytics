import Foundation

struct IssueSearchService: Sendable {
    let sources: CrashSourceLoader
    let dateProvider: DateProvider
    let lastSeen = IssueLastSeenLoader()

    // MARK: - Public API

    func search(_ request: IssuesRequest) async throws -> IssueSearchResult {
        let window = try ReportWindow(since: request.since, now: dateProvider.currentDate()).interval
        let matcher = IssueMatcher(criteria: request.criteria)
        var warnings: [CommandWarning] = []

        let client = try sources.firebaseClient(optional: request.includesXcode)
        if client == nil {
            warnings.append(Self.firebaseSkippedWarning())
        }

        let firebase = try await searchFirebase(client, request: request, matcher: matcher, window: window)
        warnings += firebase.warnings

        let xcode = try loadXcode(request: request, matcher: matcher, window: window)
        warnings += xcode.warnings

        let displayedIssues = Array(firebase.matched.prefix(request.limit))
        let displayedXcodeCrashes = Array(xcode.matched.prefix(request.limit))

        var lastSeenAt: [String: String] = [:]
        if let client {
            let loaded = try await lastSeen.load(for: displayedIssues, client: client, window: window)
            lastSeenAt = loaded.lastSeenAt
            warnings += loaded.warning.map { [$0] } ?? []
        }

        return IssueSearchResult(
            request: request,
            window: window,
            fetchLimit: firebase.fetchLimit,
            fetchedCount: firebase.fetchedCount,
            matchedCount: firebase.matched.count,
            issues: displayedIssues,
            eventMetadataSamples: firebase.samples,
            matchedVersions: firebase.matchedVersions,
            lastSeenAt: lastSeenAt,
            xcodeCrashes: displayedXcodeCrashes,
            matchedXcodeCount: xcode.matched.count,
            hint: emptyResultHint(firebase, matcher: matcher),
            symbolicationHint: symbolicationHint(
                request: request, displayedIssues: displayedIssues, displayedXcodeCrashes: displayedXcodeCrashes),
            warnings: warnings)
    }

    // MARK: - Firebase

    private struct FirebaseSearch {
        var fetchedCount = 0
        var fetchLimit = 0
        var matched: [CrashIssue] = []
        var samples = 0
        var matchedVersions: [String]?
        /// Names the versions seen in the window when none matched.
        var versionHint: String?
        var warnings: [CommandWarning] = []
    }

    private func searchFirebase(
        _ client: CrashlyticsClient?, request: IssuesRequest, matcher: IssueMatcher, window: DateInterval
    ) async throws -> FirebaseSearch {
        var search = FirebaseSearch()
        search.warnings += searchLimitCapWarning(for: request)
        guard let client else { return search }

        search.fetchLimit = IssueSearchPlanner.resolvedSearchLimit(
            outputLimit: request.limit, explicit: request.searchLimit, all: request.all,
            hasCriteria: matcher.hasSearchCriteria)

        var options = IssueQueryOptions(includesDailyCounts: request.byDay)
        if matcher.hasVersionFilter {
            let reported = try await client.fetchReportedVersions(interval: window)
            let selected = matcher.selectVersions(from: reported)
            guard !selected.isEmpty else {
                search.versionHint = IssueSearchPlanner.noVersionHint(criteria: request.criteria, reported: reported)
                search.matchedVersions = []
                return search
            }
            options.versionDisplayNames = selected.map(\.displayName)
            search.matchedVersions = options.versionDisplayNames
        }

        let fetched = try await client.fetchIssues(limit: search.fetchLimit, interval: window, options: options)
        search.fetchedCount = fetched.count
        search.matched = fetched.filter(matcher.matchesIssueFields)

        if search.matched.contains(where: matcher.requiresEventMetadata(for:)) {
            try await filterByEventMetadata(&search, request: request, matcher: matcher, client: client, window: window)
        }
        search.warnings += searchTruncatedWarning(for: search, request: request, matcher: matcher)
        return search
    }

    private func filterByEventMetadata(
        _ search: inout FirebaseSearch,
        request: IssuesRequest,
        matcher: IssueMatcher,
        client: CrashlyticsClient,
        window: DateInterval
    ) async throws {
        let metadataFilter = IssueEventMetadataFilter(matcher: matcher, eventsPerIssue: request.eventsPerIssue)
        let filtered = try await metadataFilter.apply(to: search.matched, client: client, window: window)
        search.matched = filtered.issues
        search.samples = filtered.samples
        if filtered.depthExhausted > 0 {
            search.warnings.append(Self.scanTruncatedWarning(
                issuesWithoutMatch: filtered.depthExhausted, eventsChecked: filtered.depth))
        }
    }

    private func searchLimitCapWarning(for request: IssuesRequest) -> [CommandWarning] {
        let cap = IssueSearchPlanner.allSearchLimitCap
        guard !request.all, let searchLimit = request.searchLimit, searchLimit > cap else { return [] }
        let warning = CommandWarning(
            code: .searchLimitCapped,
            message: "--search-limit \(searchLimit) exceeds the \(cap)-issue cap; using \(cap).")
        return [warning]
    }

    private func searchTruncatedWarning(
        for search: FirebaseSearch, request: IssuesRequest, matcher: IssueMatcher
    ) -> [CommandWarning] {
        let reachedCap = IssueSearchPlanner.capReached(all: request.all, fetchedCount: search.fetchedCount)
        let exhaustedWindow = IssueSearchPlanner.windowExhausted(
            hasCriteria: matcher.hasSearchCriteria,
            fetchedCount: search.fetchedCount,
            fetchLimit: search.fetchLimit,
            matchedCount: search.matched.count,
            outputLimit: request.limit)
        guard reachedCap || exhaustedWindow else { return [] }
        let warning = CommandWarning(
            code: .searchTruncated,
            message: "searched the top \(search.fetchedCount) issues by impact; "
                + "matches ranked lower were not checked.")
        return [warning]
    }

    // MARK: - Xcode

    private func loadXcode(
        request: IssuesRequest, matcher: IssueMatcher, window: DateInterval
    ) throws -> (matched: [XcodeCrash], warnings: [CommandWarning]) {
        guard request.includesXcode else { return ([], []) }
        let load = try sources.xcodeCrashes(directories: request.crashDirectories)
        var warnings = load.warnings
        if matcher.hasEventOnlyFilters {
            warnings.append(Self.xcodeExcludedWarning())
        }
        let cutoff = try request.since.flatMap { try SinceExpressionParser.cutoffDate(from: $0, now: window.end) }
        return (matcher.matchingXcodeCrashes(load.crashes, since: cutoff), warnings)
    }

    // MARK: - Hints

    private func emptyResultHint(_ firebase: FirebaseSearch, matcher: IssueMatcher) -> String? {
        firebase.versionHint ?? IssueSearchPlanner.emptyResultHint(
            hasCriteria: matcher.hasSearchCriteria,
            fetchedCount: firebase.fetchedCount,
            fetchLimit: firebase.fetchLimit,
            matchedCount: firebase.matched.count)
    }

    private func symbolicationHint(
        request: IssuesRequest, displayedIssues: [CrashIssue], displayedXcodeCrashes: [XcodeCrash]
    ) -> String? {
        let onlyXcodeCrashesShown = displayedIssues.isEmpty && request.includesXcode && !displayedXcodeCrashes.isEmpty
        guard onlyXcodeCrashesShown else { return nil }
        return SymbolicationAdvisor.hint(for: displayedXcodeCrashes)
    }

    // MARK: - Warning texts

    private static func firebaseSkippedWarning() -> CommandWarning {
        CommandWarning(
            code: .firebaseSkipped,
            message: "no Firebase appId is configured; showing local Xcode crashes only.")
    }

    private static func xcodeExcludedWarning() -> CommandWarning {
        CommandWarning(
            code: .xcodeExcludedByFilter,
            message: "--user-id, --domain and --user-info-key need Firebase event data; "
                + "local Xcode crashes were excluded.")
    }

    private static func scanTruncatedWarning(issuesWithoutMatch: Int, eventsChecked: Int) -> CommandWarning {
        CommandWarning(
            code: .scanTruncated,
            message: "--user-id: \(issuesWithoutMatch) issue(s) had no match in their newest "
                + "\(eventsChecked) events of the window; older events were not checked. "
                + "Raise --events-per-issue to look deeper.")
    }
}
