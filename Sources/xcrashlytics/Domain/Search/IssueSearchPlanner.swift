import Foundation

enum IssueSearchPlanner {
    static let defaultSearchLimit = 200
    static let allSearchLimitCap = 2_000

    static func resolvedSearchLimit(outputLimit: Int, explicit: Int?, all: Bool, hasCriteria: Bool) -> Int {
        if all {
            return allSearchLimitCap
        }
        if let explicit {
            return min(allSearchLimitCap, max(1, explicit))
        }
        if hasCriteria {
            return max(outputLimit, defaultSearchLimit)
        }
        return outputLimit
    }

    static func emptyResultHint(hasCriteria: Bool, fetchedCount: Int, fetchLimit: Int, matchedCount: Int) -> String? {
        guard hasCriteria, matchedCount == 0, fetchedCount > 0 else {
            return nil
        }
        if fetchedCount < fetchLimit {
            return "0 matches in all \(fetchedCount) fetched issues."
        }
        guard let next = nextSearchLimit(after: fetchedCount) else {
            return "0 matches in the top \(fetchedCount) issues by impact, the largest search window; "
                + "no wider scan is possible. Narrow the filters or change --since."
        }
        return "0 matches in top \(fetchedCount) by impact. Rerun with --search-limit \(next)."
    }

    static func nextSearchLimit(after fetchedCount: Int) -> Int? {
        let next = min(allSearchLimitCap, max(500, fetchedCount * 5))
        return next > fetchedCount ? next : nil
    }
}

extension IssueSearchPlanner {
    /// Newest events checked per issue for `--user-id` when `--events-per-issue` is absent.
    static let defaultUserScanDepth = 50

    /// `--all` fetched the largest window, so lower-ranked matches cannot be reached.
    static func capReached(all: Bool, fetchedCount: Int) -> Bool {
        all && fetchedCount >= allSearchLimitCap
    }

    /// A filtered search used its whole window and still found fewer matches than it shows.
    static func windowExhausted(
        hasCriteria: Bool, fetchedCount: Int, fetchLimit: Int, matchedCount: Int, outputLimit: Int
    ) -> Bool {
        hasCriteria && fetchedCount >= fetchLimit && matchedCount < outputLimit
    }

    static func noVersionHint(criteria: IssueCriteria, reported: [ReportedVersion]) -> String {
        let wanted = [
            criteria.appVersion.map { "--app-version \($0)" },
            criteria.sinceVersion.map { "--since-version \($0)" }
        ].compactMap { $0 }.joined(separator: " ")
        var seen: Set<String> = []
        let names = reported.map(\.displayName).filter { seen.insert($0).inserted }
        guard !names.isEmpty else {
            return "\(wanted) matched nothing: the app has no versions with events in this window. "
                + "Widen it with --since."
        }
        return "\(wanted) matched none of the versions with events in this window: "
            + names.joined(separator: ", ") + ". Widen the window with --since or pick one of these."
    }
}
