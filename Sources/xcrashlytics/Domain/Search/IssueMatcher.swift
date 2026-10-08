import Foundation

/// Decides whether Firebase issues, their events and local Xcode crashes satisfy the user's `IssueCriteria`.
struct IssueMatcher: Sendable {
    let criteria: IssueCriteria

    init(criteria: IssueCriteria) { self.criteria = criteria }

    // MARK: - Which criteria are set

    var hasSearchCriteria: Bool {
        hasAnyTextualCriterion || !criteria.userInfoKey.isEmpty || criteria.minEvents != nil
    }

    /// Filters only an event can answer: its user, error domain, or userInfo.
    var hasEventOnlyFilters: Bool {
        normalizedUserId != nil
            || criteria.domain?.trimmedNonEmpty != nil
            || !criteria.userInfoKey.isEmpty
    }

    /// Firebase issues are narrowed to these versions on the server, so counts cover only them.
    var hasVersionFilter: Bool {
        !criteria.versions.isEmpty
    }

    var normalizedUserId: String? {
        criteria.userId?.trimmedNonEmpty
    }

    // MARK: - Firebase issues

    func matchesIssueFields(_ issue: CrashIssue) -> Bool {
        if let minEvents = criteria.minEvents, (issue.eventsCount ?? 0) < minEvents { return false }
        if let type = criteria.type, !Self.matchesType(issue: issue, type) { return false }

        let display = IssueDisplaySignature(issue)
        if let file = criteria.file, !Self.matchesExact(display?.file, file) { return false }
        if let symbol = criteria.symbol,
           !Self.matchesSymbol(issue: issue, display: display, expected: symbol) {
            return false
        }
        return searchTerms.allSatisfy { term in
            matchesIssueText(issue, term: term) || Self.isEventMetadataQuery(term)
        }
    }

    func matchesIssueText(_ issue: CrashIssue, term: String) -> Bool {
        Self.contains(Self.searchHaystack(for: issue), term)
    }

    func requiresEventMetadata(for issue: CrashIssue) -> Bool {
        hasEventOnlyFilters || !unresolvedEventTerms(for: issue).isEmpty
    }

    /// `issue` is checked against one of its events: user, domain, userInfo,
    /// and any query term the issue's own text did not already match.
    func matchesEventMetadata(issue: CrashIssue, event: CrashlyticsEvent) -> Bool {
        let metadata = CrashlyticsEventMetadataReader(event)
        if let normalizedUserId, event.userId != normalizedUserId { return false }
        if let domain = criteria.domain, !metadata.matchesDomain(domain) { return false }
        for filter in criteria.userInfoKey where !metadata.matchesUserInfoFilter(filter) {
            return false
        }
        for term in eventSearchTerms
        where !matchesIssueText(issue, term: term) && !metadata.matches(term) {
            return false
        }
        return true
    }

    /// Versions satisfying both `--app-version` (and its build, as in `6.16.0 (937)`) and
    /// `--since-version`, collapsed to distinct display names.
    func selectVersions(from reported: [ReportedVersion]) -> [ReportedVersion] {
        var seenDisplayNames: Set<String> = []
        return reported.filter { version in
            let admitted = criteria.versions.admits(Self.versionText(version), release: version.displayVersion)
            return admitted && seenDisplayNames.insert(version.displayName).inserted
        }
    }

    /// Code-looking terms (`Foo.swift`, `my_func`, `key=value`) may name event metadata.
    static func isEventMetadataQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains(".") || trimmed.contains("_") || trimmed.contains("=")
    }

    // MARK: - Local Xcode crashes

    /// Local reports carry no user, domain, or userInfo, so those filters
    /// exclude every one of them. A report is one event, which is what
    /// `--min-events` counts.
    func matchesXcodeEvent(_ event: CrashEvent) -> Bool {
        guard !hasEventOnlyFilters else { return false }
        if let minEvents = criteria.minEvents, minEvents > 1 { return false }
        if let type = criteria.type, !Self.matchesExact(event.exception.exceptionType, type) { return false }
        if !criteria.versions.admits(event.bundleVersion) { return false }
        if let file = criteria.file, !event.frames.contains(where: { Self.matchesExact($0.file, file) }) {
            return false
        }
        if let symbol = criteria.symbol,
           !event.frames.contains(where: { Self.matchesExact($0.symbol, symbol) }) {
            return false
        }
        let haystack = Self.xcodeSearchHaystack(event)
        return searchTerms.allSatisfy { Self.contains(haystack, $0) }
    }

    /// Local crashes that pass the filters. A `nil` cutoff means no time limit; a crash
    /// without a timestamp cannot satisfy one.
    func matchingXcodeCrashes(_ crashes: [XcodeCrash], since cutoff: Date?) -> [XcodeCrash] {
        crashes.filter { crash in
            guard matchesXcodeEvent(crash.event) else { return false }
            guard let cutoff else { return true }
            guard let timestamp = crash.event.timestamp else { return false }
            return timestamp >= cutoff
        }
    }

    // MARK: - Search terms

    private var hasAnyTextualCriterion: Bool {
        let textualCriteria = [
            criteria.query,
            criteria.match,
            criteria.type,
            criteria.appVersion,
            criteria.sinceVersion,
            criteria.file,
            criteria.symbol,
            criteria.userId,
            criteria.domain,
        ]
        return textualCriteria.contains { $0?.trimmedNonEmpty != nil }
    }

    private var searchTerms: [String] {
        [criteria.query, criteria.match].compactMap { $0?.trimmedNonEmpty }
    }

    private var eventSearchTerms: [String] {
        searchTerms.filter(Self.isEventMetadataQuery)
    }

    /// An issue whose own text matches a code-looking term is already a match.
    func unresolvedEventTerms(for issue: CrashIssue) -> [String] {
        eventSearchTerms.filter { !matchesIssueText(issue, term: $0) }
    }

    // MARK: - Text matching

    private static func contains(_ haystack: String, _ term: String) -> Bool {
        haystack.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func searchHaystack(for issue: CrashIssue) -> String {
        let display = IssueDisplaySignature(issue)
        return [
            issue.exception.description,
            issue.exception.subtype,
            issue.exception.exceptionType,
            issue.exception.signal,
            issue.bundleVersion,
            display?.module,
            display?.file,
            display?.symbol,
            CrashSignature.of(issue)?.symbol,
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func xcodeSearchHaystack(_ event: CrashEvent) -> String {
        [
            event.exception.exceptionType,
            event.exception.signal,
            event.exception.subtype,
            event.bundleId,
            event.bundleVersion,
            event.osVersion,
            event.deviceModel,
            event.frames.compactMap(\.file).joined(separator: " "),
            event.frames.compactMap(\.symbol).joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func matchesExact(_ actual: String?, _ expected: String) -> Bool {
        guard !expected.isEmpty, let actual else { return false }
        return actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// `--type` names Firebase's error type (FATAL, NON_FATAL, ANR) or the
    /// exception type (EXC_BAD_ACCESS).
    private static func matchesType(issue: CrashIssue, _ expected: String) -> Bool {
        matchesExact(issue.errorType, expected) || matchesExact(issue.exception.exceptionType, expected)
    }

    private static func matchesSymbol(issue: CrashIssue, display: IssueDisplaySignature?, expected: String) -> Bool {
        matchesExact(display?.symbol, expected)
            || matchesExact(CrashSignature.of(issue)?.symbol, expected)
    }

    private static func versionText(_ version: ReportedVersion) -> String {
        version.buildVersion.map { "\(version.displayVersion) (\($0))" } ?? version.displayVersion
    }
}
