import Foundation
import Testing
@testable import xcrashlytics

@Suite("since duration")
struct SinceDurationTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("parses d/h/m suffixes")
    func parses() throws {
        #expect(try SinceDuration.cutoffDate(from: "7d", now: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(try SinceDuration.cutoffDate(from: "24h", now: now) == now.addingTimeInterval(-24 * 3_600))
        #expect(try SinceDuration.cutoffDate(from: "30m", now: now) == now.addingTimeInterval(-30 * 60))
    }

    @Test("all and none mean no cutoff")
    func allMeansNil() throws {
        #expect(try SinceDuration.cutoffDate(from: "all", now: now) == nil)
        #expect(try SinceDuration.cutoffDate(from: "none", now: now) == nil)
    }

    @Test("garbage throws SinceDurationError")
    func garbageThrows() {
        #expect(throws: SinceDurationError.invalid("7x")) {
            _ = try SinceDuration.cutoffDate(from: "7x", now: now)
        }
    }
}
