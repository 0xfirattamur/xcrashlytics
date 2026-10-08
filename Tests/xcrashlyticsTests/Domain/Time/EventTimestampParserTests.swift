import Foundation
import Testing
@testable import xcrashlytics

@Suite("event dates")
struct EventTimestampParserTests {
    @Test("dayString buckets to UTC calendar days")
    func dayString() {
        #expect(EventTimestampParser.dayString(from: "2026-06-10T23:59:59Z") == "2026-06-10")
        #expect(EventTimestampParser.dayString(from: nil) == nil)
        #expect(EventTimestampParser.dayString(from: "garbage") == nil)
    }

    @Test("accepts offsets and fractional seconds; day buckets are UTC")
    func offsetsAndFractions() throws {
        let whole = try #require(EventTimestampParser.parse("2026-06-10T12:00:00Z"))
        let fractional = try #require(EventTimestampParser.parse("2026-06-10T12:00:00.500Z"))
        #expect(fractional.timeIntervalSince(whole) == 0.5)
        #expect(EventTimestampParser.parse("2026-06-10T12:00:00+02:00") == EventTimestampParser.parse("2026-06-10T10:00:00Z"))
        #expect(EventTimestampParser.parse("2026-06-10T12:00:00.123456789Z") != nil)
        #expect(EventTimestampParser.parse("not a date") == nil)
        #expect(EventTimestampParser.dayString(from: "2026-06-10T23:30:00-05:00") == "2026-06-11")
    }

    @Test("lowercase, zoneless and date-only timestamps are unparseable")
    func rejectsLooseForms() {
        #expect(EventTimestampParser.parse("2026-06-10t12:00:00z") == nil)
        #expect(EventTimestampParser.parse("2026-06-10T12:00:00") == nil)
        #expect(EventTimestampParser.parse("2026-06-10") == nil)
    }

    @Test("a cutoff excludes unparseable and missing times; no cutoff admits everything")
    func isIncluded() {
        let cutoff = EventTimestampParser.parse("2026-06-10T00:00:00Z")
        #expect(EventTimestampParser.isIncluded(event: CrashlyticsEvent(eventTime: "2026-06-10T00:00:00Z"), onOrAfter: cutoff))
        #expect(!EventTimestampParser.isIncluded(event: CrashlyticsEvent(eventTime: "2026-06-09T23:59:59Z"), onOrAfter: cutoff))
        #expect(!EventTimestampParser.isIncluded(event: CrashlyticsEvent(eventTime: nil), onOrAfter: cutoff))
        #expect(!EventTimestampParser.isIncluded(event: CrashlyticsEvent(eventTime: "soon"), onOrAfter: cutoff))
        #expect(EventTimestampParser.isIncluded(event: CrashlyticsEvent(eventTime: nil), onOrAfter: nil))
    }
}
