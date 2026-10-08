import Foundation
import Testing
@testable import xcrashlytics

@Suite("issue activity summary")
struct IssueActivitySummaryTests {
    private func event(
        time: String?, os: String? = nil, device: String? = nil, user: String? = nil
    ) throws -> CrashlyticsEvent {
        var fields = [#""eventId": "E""#]
        if let time { fields.append(#""eventTime": "\#(time)""#) }
        fields.append(#""platform": "IOS""#)
        if let os { fields.append(#""operatingSystem": {"displayVersion": "\#(os)"}"#) }
        if let device { fields.append(#""device": {"model": "\#(device)"}"#) }
        if let user { fields.append(#""user": {"id": "\#(user)"}"#) }
        let json = "{\(fields.joined(separator: ","))}"
        return try CrashlyticsEventDTOMapper().event(from: JSONDecoder().decode(CrashlyticsDTO.Event.self, from: Data(json.utf8)))
    }

    @Test("summarises date range, spreads, and distinct users from sampled events")
    func summarisesSample() throws {
        let events = [
            try event(time: "2026-06-10T08:00:00Z", os: "26.4.1", device: "iPhone 17 Pro Max", user: "u1"),
            try event(time: "2026-06-09T08:00:00Z", os: "26.4.1", device: "iPhone 16", user: "u2"),
            try event(time: "2026-06-01T08:00:00Z", os: "26.3.0", device: "iPhone 17 Pro Max", user: "u1"),
        ]
        let summary = IssueActivitySummary(events: events)
        #expect(summary.sampledEvents == 3)
        #expect(summary.firstEventAt == "2026-06-01T08:00:00Z")
        #expect(summary.lastEventAt == "2026-06-10T08:00:00Z")
        #expect(summary.osSpread == [
            SpreadCount(name: "iOS 26.4.1", count: 2),
            SpreadCount(name: "iOS 26.3.0", count: 1),
        ])
        #expect(summary.deviceSpread == [
            SpreadCount(name: "iPhone 17 Pro Max", count: 2),
            SpreadCount(name: "iPhone 16", count: 1),
        ])
        #expect(summary.distinctUsers == 2)
    }

    @Test("missing metadata yields empty spreads and nil users")
    func emptyMetadata() throws {
        let summary = IssueActivitySummary(events: [try event(time: nil)])
        #expect(summary.sampledEvents == 1)
        #expect(summary.firstEventAt == nil)
        #expect(summary.lastEventAt == nil)
        #expect(summary.osSpread.isEmpty)
        #expect(summary.deviceSpread.isEmpty)
        #expect(summary.distinctUsers == nil)
    }

    @Test("ties in spread counts break by name for stable output")
    func stableTieBreak() throws {
        let events = [
            try event(time: nil, device: "iPhone 16"),
            try event(time: nil, device: "iPhone 15"),
        ]
        let summary = IssueActivitySummary(events: events)
        #expect(summary.deviceSpread.map(\.name) == ["iPhone 15", "iPhone 16"])
    }

    @Test("first and last event compare dates, not strings, across offsets and fractions")
    func ordersByInstant() throws {
        let events = [
            try event(time: "2026-06-10T09:00:00+02:00"),  // 07:00Z
            try event(time: "2026-06-10T08:00:00Z"),
            try event(time: "2026-06-10T07:30:00.5Z"),
            try event(time: "garbage"),
        ]
        let summary = IssueActivitySummary(events: events)
        #expect(summary.firstEventAt == "2026-06-10T09:00:00+02:00")
        #expect(summary.lastEventAt == "2026-06-10T08:00:00Z")
    }

    @Test("OS label follows the event platform instead of assuming iOS")
    func platformLabels() throws {
        func decode(_ json: String) throws -> CrashlyticsEvent {
            try CrashlyticsEventDTOMapper().event(from: JSONDecoder().decode(CrashlyticsDTO.Event.self, from: Data(json.utf8)))
        }
        let events = [
            try decode(#"{"eventId":"A","platform":"ANDROID","operatingSystem":{"displayVersion":"15"}}"#),
            try decode(#"{"eventId":"B","platform":"IOS","operatingSystem":{"displayVersion":"26.4.1"}}"#),
            try decode(#"{"eventId":"C","operatingSystem":{"displayVersion":"9"}}"#),
        ]
        let names = Set(IssueActivitySummary(events: events).osSpread.map(\.name))
        #expect(names == ["Android 15", "iOS 26.4.1", "9"])
    }
}
