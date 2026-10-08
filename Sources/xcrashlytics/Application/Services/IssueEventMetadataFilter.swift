import Foundation

struct IssueEventMetadataFilter: Sendable {
    struct Outcome: Sendable {
        var issues: [CrashIssue]
        var samples: Int
        /// `--user-id` only: issues whose whole sample held no match.
        var depthExhausted: Int
        var depth: Int
    }

    let matcher: IssueMatcher
    let eventsPerIssue: Int?

    /// An issue that needs events but has none is dropped: nothing confirms it.
    func apply(to issues: [CrashIssue], client: CrashlyticsClient, window: DateInterval) async throws -> Outcome {
        let depth = scanDepth()
        let needsEvents = issues.filter(matcher.requiresEventMetadata(for:))
        let sampled = try await IssueEventSampler(firebase: client, eventsPerIssue: depth, interval: window)
            .sample(issues: needsEvents)
        var matchedIds: Set<String> = []
        var samples = 0
        var depthExhausted = 0
        for sample in sampled {
            samples += sample.events.count
            if sample.events.contains(where: { matcher.matchesEventMetadata(issue: sample.issue, event: $0) }) {
                matchedIds.insert(sample.issue.id)
            } else if matcher.normalizedUserId != nil, sample.events.count >= depth {
                depthExhausted += 1
            }
        }
        let kept = issues.filter { !matcher.requiresEventMetadata(for: $0) || matchedIds.contains($0.id) }
        return Outcome(issues: kept, samples: samples, depthExhausted: depthExhausted, depth: depth)
    }

    /// One event settles a metadata check; a `--user-id` scan looks deeper.
    private func scanDepth() -> Int {
        guard matcher.normalizedUserId != nil else { return 1 }
        return eventsPerIssue ?? IssueSearchPlanner.defaultUserScanDepth
    }
}
