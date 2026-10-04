//
//  IssueFilter.swift
//  xcrashlytics
//

import Foundation

/// Everything the user asked `issues` to narrow by.
public struct IssueSearchCriteria: Sendable {
    public var query: String?
    public var match: String?
    public var type: String?
    public var minEvents: Int?
    public var appVersion: String?
    public var sinceVersion: String?
    public var file: String?
    public var symbol: String?
    public var domain: String?
    public var userInfoKey: [String]
    public var userId: String?

    public init(
        query: String? = nil, match: String? = nil, type: String? = nil,
        minEvents: Int? = nil, appVersion: String? = nil, sinceVersion: String? = nil,
        file: String? = nil, symbol: String? = nil, domain: String? = nil,
        userInfoKey: [String] = [], userId: String? = nil
    ) {
        self.query = query; self.match = match; self.type = type
        self.minEvents = minEvents; self.appVersion = appVersion; self.sinceVersion = sinceVersion
        self.file = file; self.symbol = symbol; self.domain = domain
        self.userInfoKey = userInfoKey; self.userId = userId
    }
}

/// Pure matching logic for issue search — no I/O, fully testable.
public struct IssueFilter: Sendable {
    public let criteria: IssueSearchCriteria

    public init(criteria: IssueSearchCriteria) { self.criteria = criteria }

    public var hasSearchCriteria: Bool {
        [
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
        .contains { value in
            value?.trimmedNonEmpty != nil
        } || !criteria.userInfoKey.isEmpty
    }

    public var searchTerms: [String] {
        [criteria.query, criteria.match]
            .compactMap { $0?.trimmedNonEmpty }
    }

    public var eventSearchTerms: [String] {
        searchTerms.filter(Self.isEventMetadataQuery)
    }

    public var requiresEventMetadataSearch: Bool {
        normalizedUserId != nil
            || criteria.domain?.trimmedNonEmpty != nil
            || !criteria.userInfoKey.isEmpty
            || !eventSearchTerms.isEmpty
    }

    public var normalizedUserId: String? {
        criteria.userId?.trimmedNonEmpty
    }

    public func matchesIssueFields(_ issue: CrashIssue) -> Bool {
        if let minEvents = criteria.minEvents, (issue.eventsCount ?? 0) < minEvents { return false }
        if let type = criteria.type, !type.isEmpty,
            issue.exception.exceptionType.caseInsensitiveCompare(type) != .orderedSame {
            return false
        }
        if let appVersion = criteria.appVersion, !Self.matchesSeenVersion(issue, appVersion) {
            return false
        }
        if let sinceVersion = criteria.sinceVersion,
            !VersionComparator.isAtLeast(issue.bundleVersion, sinceVersion) {
            return false
        }
        let display = DisplaySignature(issue)
        if let file = criteria.file, !Self.matchesExact(display?.file, file) {
            return false
        }
        if let symbol = criteria.symbol, !Self.matchesSymbol(issue: issue, display: display, expected: symbol) {
            return false
        }
        return searchTerms.allSatisfy { term in
            matchesIssueText(issue, term: term) || Self.isEventMetadataQuery(term)
        }
    }

    public func matchesXcodeEvent(_ event: CrashEvent) -> Bool {
        guard normalizedUserId == nil, criteria.domain?.trimmedNonEmpty == nil,
              criteria.userInfoKey.isEmpty else { return false }
        if let type = criteria.type, !type.isEmpty,
           event.exception.exceptionType.caseInsensitiveCompare(type) != .orderedSame {
            return false
        }
        if let appVersion = criteria.appVersion,
           !Self.matchesExact(event.bundleVersion, appVersion) {
            return false
        }
        if let file = criteria.file,
           !event.frames.contains(where: { Self.matchesExact($0.file, file) }) {
            return false
        }
        if let symbol = criteria.symbol,
           !event.frames.contains(where: { Self.matchesExact($0.symbol, symbol) }) {
            return false
        }
        return searchTerms.allSatisfy {
            Self.xcodeSearchHaystack(event).range(
                of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
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

    public func matchesIssueText(_ issue: CrashIssue, term: String) -> Bool {
        Self.searchHaystack(for: issue).range(
            of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public func matchesEventMetadata(issue: CrashIssue, event: FirebaseEvent) -> Bool {
        let metadata = FirebaseEventMetadata(event)
        if let normalizedUserId, event.userId != normalizedUserId {
            return false
        }
        if let domain = criteria.domain, !metadata.matchesDomain(domain) {
            return false
        }
        for filter in criteria.userInfoKey where !metadata.matchesUserInfoFilter(filter) {
            return false
        }
        for term in eventSearchTerms
        where !matchesIssueText(issue, term: term) && !metadata.matches(term) {
            return false
        }
        return true
    }

    public static func isEventMetadataQuery(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains(".") || trimmed.contains("_") || trimmed.contains("=")
    }

    public static func searchHaystack(for issue: CrashIssue) -> String {
        let display = DisplaySignature(issue)
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

    static func matchesExact(_ value: String?, _ expected: String) -> Bool {
        guard !expected.isEmpty, let value else { return false }
        return value.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// Matches an exact version against either end of the issue's seen range.
    /// Versions between first- and last-seen are not reported by Firebase.
    static func matchesSeenVersion(_ issue: CrashIssue, _ expected: String) -> Bool {
        matchesExact(issue.bundleVersion, expected)
            || matchesExact(issue.firstSeenVersion, expected)
    }

    static func matchesSymbol(issue: CrashIssue, display: DisplaySignature?, expected: String) -> Bool {
        matchesExact(display?.symbol, expected)
            || matchesExact(CrashSignature.of(issue)?.symbol, expected)
    }
}

/// Search-window sizing and the empty-result hint ladder.
public enum IssueSearchPlanner {
    public static let defaultSearchLimit = 200
    public static let allSearchLimitCap = 2_000

    public static func resolvedSearchLimit(outputLimit: Int, explicit: Int?, all: Bool, hasCriteria: Bool) -> Int {
        if all {
            return allSearchLimitCap
        }
        if let explicit {
            return max(1, explicit)
        }
        if hasCriteria {
            return max(outputLimit, defaultSearchLimit)
        }
        return outputLimit
    }

    public static func emptyResultHint(hasCriteria: Bool, fetchedCount: Int, fetchLimit: Int, matchedCount: Int) -> String? {
        guard hasCriteria, matchedCount == 0, fetchedCount > 0 else {
            return nil
        }
        if fetchedCount < fetchLimit {
            return "0 matches in all \(fetchedCount) fetched issues."
        }
        let next = nextSearchLimit(after: fetchedCount)
        if let next {
            return "0 matches in top \(fetchedCount) by impact. Rerun with --search-limit \(next)."
        }
        return "0 matches in top \(fetchedCount) by impact. Rerun with --all."
    }

    static func nextSearchLimit(after fetchedCount: Int) -> Int? {
        let next = min(allSearchLimitCap, max(500, fetchedCount * 5))
        return next > fetchedCount ? next : nil
    }
}
