import Foundation

struct IssueLastSeenLoader: Sendable {
    struct Outcome: Sendable {
        var lastSeenAt: [String: String] = [:]
        var warning: CommandWarning?
    }

    /// Best effort: a failure drops the field for that issue and warns.
    func load(for issues: [CrashIssue], client: CrashlyticsClient, window: DateInterval) async throws -> Outcome {
        guard !issues.isEmpty else { return Outcome() }
        let sampled = try await IssueEventSampler(firebase: client, eventsPerIssue: 1, interval: window)
            .sample(issues: issues, bestEffort: true)
        var outcome = Outcome()
        var failures: [String] = []
        for sample in sampled {
            if let failure = sample.failure {
                failures.append(failure)
            } else if let newestTime = Self.newestEventTime(in: sample.events) {
                outcome.lastSeenAt[sample.issue.id] = newestTime
            }
        }
        if let first = failures.first {
            outcome.warning = CommandWarning(
                code: .lastSeenUnavailable,
                message: "could not read recent events for \(failures.count) of \(issues.count) issues, "
                    + "so lastSeenAt is omitted for them: \(first)")
        }
        return outcome
    }

    /// The raw timestamp string of the newest event whose time parses.
    private static func newestEventTime(in events: [CrashlyticsEvent]) -> String? {
        let timed: [(date: Date, raw: String)] = events.compactMap { event in
            guard let raw = event.eventTime, let date = EventTimestampParser.parse(raw) else { return nil }
            return (date, raw)
        }
        return timed.max { $0.date < $1.date }?.raw
    }
}
