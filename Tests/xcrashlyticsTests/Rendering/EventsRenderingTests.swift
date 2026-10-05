import Foundation
import Testing
@testable import xcrashlytics

@Suite("events rendering")
struct EventsRenderingTests {
    private func event(_ json: String) throws -> FirebaseEvent {
        try JSONDecoder().decode(FirebaseDTO.EventDTO.self, from: Data(json.utf8)).toFirebaseEvent()
    }

    @Test("rows omit unknown placeholders instead of printing them")
    func unknownSegmentsAreDropped() throws {
        let bare = try event(#"{"eventId":"E1","eventTime":"2026-06-10T12:00:00Z"}"#)
        let out = EventsRenderer.text(
            [IssueEvents(issueId: "I1", events: [bare])],
            frameOptions: FirebaseFrameFilterOptions()
        )
        #expect(out.contains("2026-06-10T12:00:00Z"))
        #expect(!out.contains("unknown RAM"))
        #expect(!out.contains("unknown app"))
        #expect(!out.contains("unknown device"))
        #expect(!out.contains("unknown OS"))
    }

    @Test("partially known runtime renders the known half only")
    func partialRuntime() throws {
        let deviceOnly = try event(#"""
        {"eventId":"E1","device":{"model":"iPhone 17 Pro Max"}}
        """#)
        let out = EventsRenderer.text(
            [IssueEvents(issueId: "I1", events: [deviceOnly])],
            frameOptions: FirebaseFrameFilterOptions()
        )
        #expect(out.contains("iPhone 17 Pro Max"))
        #expect(!out.contains("unknown OS"))
        #expect(!out.contains("/ unknown"))
    }

    @Test("known memory still renders free RAM")
    func knownMemory() throws {
        let withMemory = try event(#"""
        {"eventId":"E1","memory":{"free":"675335168"}}
        """#)
        let out = EventsRenderer.text(
            [IssueEvents(issueId: "I1", events: [withMemory])],
            frameOptions: FirebaseFrameFilterOptions()
        )
        #expect(out.contains("644.05 MiB free RAM"))
    }
}
