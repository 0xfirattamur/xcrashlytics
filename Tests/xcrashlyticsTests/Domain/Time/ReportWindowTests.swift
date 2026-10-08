import Foundation
import Testing
@testable import xcrashlytics

@Suite("report window")
struct ReportWindowTests {
    let now = Date(timeIntervalSince1970: 200_000_000)

    @Test("no --since is the last 7 days; all and none are 90 days")
    func defaults() throws {
        #expect(try ReportWindow(since: nil, now: now).interval == DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now))
        #expect(try ReportWindow(since: "all", now: now) == .maximum(now: now))
        #expect(try ReportWindow(since: "none", now: now).interval.end == now)
    }

    @Test("90 days is accepted; longer or malformed values are rejected as BAD_INPUT")
    func limits() throws {
        #expect(try ReportWindow(since: "90d", now: now).interval.duration == 90 * 86_400)
        #expect(try ReportWindow(since: "12w", now: now).interval.duration == 84 * 86_400)
        for bad in ["91d", "13w", "0d", "-1d", "soon"] {
            #expect(throws: (any Error).self) { _ = try ReportWindow(since: bad, now: now) }
        }
    }

    @Test("an over-long window reports the Crashlytics limit")
    func limitMessage() {
        #expect(throws: InvalidInputError(
            "--since must be a window of at most 90d (the Crashlytics limit), e.g. 7d or 30d; got '91d'.")
        ) {
            _ = try ReportWindow(since: "91d", now: now)
        }
        #expect(CommandRunner.failure(for: InvalidInputError("x")).code == "BAD_INPUT")
    }
}
