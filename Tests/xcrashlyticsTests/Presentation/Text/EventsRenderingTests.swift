import Foundation
import Testing
@testable import xcrashlytics

@Suite("events rendering")
struct EventsRenderingTests {
    private func event(_ json: String) throws -> CrashlyticsEvent {
        let dto = try JSONDecoder().decode(CrashlyticsDTO.Event.self, from: Data(json.utf8))
        return CrashlyticsEventDTOMapper().event(from: dto)
    }

    @Test("rows omit unknown placeholders instead of printing them")
    func unknownSegmentsAreDropped() throws {
        let bare = try event(#"{"eventId":"E1","eventTime":"2026-06-10T12:00:00Z"}"#)
        let output = EventsTextRenderer().text(
            [IssueEvents(issueId: "I1", events: [bare])],
            filter: .none, selector: FrameSelector()
        )
        #expect(output.contains("2026-06-10T12:00:00Z"))
        #expect(!output.contains("unknown RAM"))
        #expect(!output.contains("unknown app"))
        #expect(!output.contains("unknown device"))
        #expect(!output.contains("unknown OS"))
    }

    @Test("partially known runtime renders the known half only")
    func partialRuntime() throws {
        let deviceOnly = try event(#"""
        {"eventId":"E1","device":{"model":"iPhone 17 Pro Max"}}
        """#)
        let output = EventsTextRenderer().text(
            [IssueEvents(issueId: "I1", events: [deviceOnly])],
            filter: .none, selector: FrameSelector()
        )
        #expect(output.contains("iPhone 17 Pro Max"))
        #expect(!output.contains("unknown OS"))
        #expect(!output.contains("/ unknown"))
    }
}
