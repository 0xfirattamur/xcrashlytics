import Foundation
import Testing
@testable import xcrashlytics

@Suite("issue event sampler")
struct IssueEventSamplerTests {
    actor CallTracker {
        private(set) var active = 0
        private(set) var maxActive = 0
        private(set) var calls: [String] = []

        func begin(_ issueID: String) {
            active += 1
            maxActive = max(maxActive, active)
            calls.append(issueID)
        }

        func end() {
            active -= 1
        }
    }

    struct TrackingClient: CrashlyticsAPI {
        let tracker: CallTracker

        func listIssues(maxIssues: Int?) async throws -> [CrashIssue] { [] }
        func representativeFrames(issueID: String) async throws -> [Frame] { [] }
        func getIssueDetail(id: String) async throws -> CrashIssue {
            throw FirebaseError.apiError(code: -1, message: "unused in sampler tests")
        }
        func listEvents(issueID: String, maxEvents: Int?) async throws -> [FirebaseEvent] {
            await tracker.begin(issueID)
            try await Task.sleep(nanoseconds: 20_000_000)
            await tracker.end()
            return []
        }
    }

    func makeIssue(_ id: String) -> CrashIssue {
        CrashIssue(providerId: id, exceptionType: "FATAL")
    }

    @Test("runs at most `concurrency` requests in parallel, and more than one")
    func boundedParallelism() async throws {
        let tracker = CallTracker()
        let sampler = IssueEventSampler(
            firebase: TrackingClient(tracker: tracker), eventsPerIssue: 1, concurrency: 3)
        _ = try await sampler.sample(issues: (0..<10).map { makeIssue("I\($0)") })
        #expect(await tracker.maxActive <= 3)
        #expect(await tracker.maxActive >= 2)
        #expect(await tracker.calls.count == 10)
    }

    @Test("results preserve input order")
    func inputOrder() async throws {
        let tracker = CallTracker()
        let sampler = IssueEventSampler(
            firebase: TrackingClient(tracker: tracker), eventsPerIssue: 1, concurrency: 4)
        let samples = try await sampler.sample(issues: (0..<8).map { makeIssue("I\($0)") })
        #expect(samples.map(\.issue.providerId) == (0..<8).map { "I\($0)" })
    }
}
