import Foundation
import Testing
@testable import xcrashlytics

@Suite("event dates")
struct EventDatesTests {
    @Test("parses ISO8601 with and without fractional seconds")
    func parses() {
        #expect(EventDates.parse("2026-06-10T12:00:00Z") != nil)
        #expect(EventDates.parse("2026-06-10T12:00:00.500Z") != nil)
        #expect(EventDates.parse("not a date") == nil)
    }

    @Test("dayString buckets to UTC calendar days")
    func dayString() {
        #expect(EventDates.dayString(from: "2026-06-10T23:59:59Z") == "2026-06-10")
        #expect(EventDates.dayString(from: nil) == nil)
        #expect(EventDates.dayString(from: "garbage") == nil)
    }
}
