import Foundation
import Testing
@testable import xcrashlytics

@Suite("issue event sampler")
struct IssueEventSamplerTests {
    actor CallTracker {
        private(set) var active = 0
        private(set) var maxActive = 0
        private(set) var calls: [String] = []

        func begin(_ issueId: String) {
            active += 1
            maxActive = max(maxActive, active)
            calls.append(issueId)
        }

        func end() {
            active -= 1
        }
    }

    struct TrackingClient: CrashlyticsClient {
        let tracker: CallTracker

        func fetchIssues(
            limit: Int?, interval: DateInterval?, options: IssueQueryOptions
        ) async throws -> [CrashIssue] { [] }
        func fetchIssue(id: String) async throws -> CrashIssue {
            throw CrashlyticsClientError.apiError(code: -1, message: "unused in sampler tests")
        }
        func fetchIssueImpact(issueId: String, since: Date, until: Date, maxPages: Int) async throws -> IssueImpact? {
            throw CrashlyticsClientError.apiError(code: -1, message: "unused in sampler tests")
        }
        func fetchReportedVersions(interval: DateInterval) async throws -> [ReportedVersion] { [] }
        func fetchDailyEventCounts(
            issueId: String, interval: DateInterval
        ) async throws -> [DailyEventCount] { [] }
        func fetchBreakdown(
            issueId: String?, dimension: BreakdownDimension, interval: DateInterval
        ) async throws -> [BreakdownRow] { [] }
        func fetchEvents(issueId: String, limit: Int?, interval: DateInterval) async throws -> [CrashlyticsEvent] {
            await tracker.begin(issueId)
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
            firebase: TrackingClient(tracker: tracker), eventsPerIssue: 1, interval: Self.window, concurrency: 3)
        _ = try await sampler.sample(issues: (0..<10).map { makeIssue("I\($0)") })
        #expect(await tracker.maxActive <= 3)
        #expect(await tracker.maxActive >= 2)
        #expect(await tracker.calls.count == 10)
    }

    @Test("results preserve input order")
    func inputOrder() async throws {
        let tracker = CallTracker()
        let sampler = IssueEventSampler(
            firebase: TrackingClient(tracker: tracker), eventsPerIssue: 1, interval: Self.window, concurrency: 4)
        let samples = try await sampler.sample(issues: (0..<8).map { makeIssue("I\($0)") })
        #expect(samples.map(\.issue.providerId) == (0..<8).map { "I\($0)" })
    }

    struct FlakyClient: CrashlyticsClient {
        func fetchIssues(
            limit: Int?, interval: DateInterval?, options: IssueQueryOptions
        ) async throws -> [CrashIssue] { [] }
        func fetchIssue(id: String) async throws -> CrashIssue { throw CrashlyticsClientError.notFound("unused") }
        func fetchIssueImpact(issueId: String, since: Date, until: Date, maxPages: Int) async throws -> IssueImpact? { nil }
        func fetchReportedVersions(interval: DateInterval) async throws -> [ReportedVersion] { [] }
        func fetchDailyEventCounts(
            issueId: String, interval: DateInterval
        ) async throws -> [DailyEventCount] { [] }
        func fetchBreakdown(
            issueId: String?, dimension: BreakdownDimension, interval: DateInterval
        ) async throws -> [BreakdownRow] { [] }
        func fetchEvents(issueId: String, limit: Int?, interval: DateInterval) async throws -> [CrashlyticsEvent] {
            if issueId == "BAD" { throw CrashlyticsClientError.apiError(code: 503, message: "backend unavailable") }
            return [CrashlyticsEvent(eventId: "E-\(issueId)")]
        }
    }

    @Test("a failing request aborts the sample unless best-effort")
    func failureModes() async throws {
        let sampler = IssueEventSampler(firebase: FlakyClient(), eventsPerIssue: 1, interval: Self.window)
        let issues = ["A", "BAD", "C"].map(makeIssue)
        await #expect(throws: CrashlyticsClientError.self) {
            _ = try await sampler.sample(issues: issues)
        }
        let samples = try await sampler.sample(issues: issues, bestEffort: true)
        #expect(samples.map(\.events.count) == [1, 0, 1])
        #expect(samples.map { $0.failure != nil } == [false, true, false])
        #expect(samples[1].failure?.contains("backend unavailable") == true)
    }

    static let window = DateInterval(
        start: Date(timeIntervalSince1970: 1_700_000_000 - 7 * 86_400),
        end: Date(timeIntervalSince1970: 1_700_000_000))
}
