import Foundation

/// At most `concurrency` requests in flight; results come back in input order.
struct IssueEventSampler: Sendable {
    var firebase: CrashlyticsClient
    var eventsPerIssue: Int
    var interval: DateInterval
    var concurrency: Int

    init(firebase: CrashlyticsClient, eventsPerIssue: Int, interval: DateInterval, concurrency: Int = 6) {
        self.firebase = firebase
        self.eventsPerIssue = max(1, eventsPerIssue)
        self.interval = interval
        self.concurrency = max(1, concurrency)
    }

    /// `bestEffort` records a failed request on its sample instead of aborting the rest.
    func sample(issues: [CrashIssue], bestEffort: Bool = false) async throws -> [IssueEventSample] {
        var samples: [IssueEventSample] = []
        try await withThrowingTaskGroup(of: IssueEventSample.self) { group in
            var iterator = issues.enumerated().makeIterator()
            let width = max(1, min(concurrency, issues.count))
            for _ in 0..<width {
                enqueueNext(from: &iterator, into: &group, bestEffort: bestEffort)
            }
            while let sample = try await group.next() {
                samples.append(sample)
                enqueueNext(from: &iterator, into: &group, bestEffort: bestEffort)
            }
        }
        return samples.sorted { $0.index < $1.index }
    }

    private func enqueueNext(
        from iterator: inout EnumeratedSequence<[CrashIssue]>.Iterator,
        into group: inout ThrowingTaskGroup<IssueEventSample, Error>,
        bestEffort: Bool
    ) {
        guard let (index, issue) = iterator.next() else { return }
        let firebase = firebase
        let eventsPerIssue = eventsPerIssue
        let interval = interval
        group.addTask {
            do {
                let events = try await firebase.fetchEvents(
                    issueId: issue.providerId, limit: eventsPerIssue, interval: interval)
                return IssueEventSample(index: index, issue: issue, events: events)
            } catch where bestEffort && !(error is CancellationError) {
                return IssueEventSample(
                    index: index, issue: issue, events: [],
                    failure: FailureMapper.failure(for: error).message)
            }
        }
    }
}
