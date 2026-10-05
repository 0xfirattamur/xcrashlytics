//
//  IssueEventSampler.swift
//  xcrashlytics
//

import Foundation

/// One issue's sampled events, tagged with its position in the input list.
struct IssueEventSample: Sendable {
    var index: Int
    var issue: CrashIssue
    var events: [FirebaseEvent]

}

/// Fetches sample events for many issues with a sliding window of at most
/// `concurrency` requests in flight. Results come back in input order.
struct IssueEventSampler: Sendable {
    var firebase: CrashlyticsAPI
    var eventsPerIssue: Int
    var concurrency: Int

    init(firebase: CrashlyticsAPI, eventsPerIssue: Int, concurrency: Int = 6) {
        self.firebase = firebase
        self.eventsPerIssue = max(1, eventsPerIssue)
        self.concurrency = max(1, concurrency)
    }

    func sample(issues: [CrashIssue]) async throws -> [IssueEventSample] {
        var samples: [IssueEventSample] = []
        try await withThrowingTaskGroup(of: IssueEventSample.self) { group in
            var iterator = issues.enumerated().makeIterator()
            let width = max(1, min(concurrency, issues.count))
            for _ in 0..<width {
                enqueueNext(from: &iterator, into: &group)
            }
            while let sample = try await group.next() {
                samples.append(sample)
                enqueueNext(from: &iterator, into: &group)
            }
        }
        return samples.sorted { $0.index < $1.index }
    }

    private func enqueueNext(
        from iterator: inout EnumeratedSequence<[CrashIssue]>.Iterator,
        into group: inout ThrowingTaskGroup<IssueEventSample, Error>
    ) {
        guard let (index, issue) = iterator.next() else { return }
        let firebase = firebase
        let eventsPerIssue = eventsPerIssue
        group.addTask {
            let events = try await firebase.listEvents(issueID: issue.providerId, maxEvents: eventsPerIssue)
            return IssueEventSample(index: index, issue: issue, events: events)
        }
    }
}
