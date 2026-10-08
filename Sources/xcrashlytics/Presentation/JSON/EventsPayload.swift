import Foundation

struct EventsPayload<Event: Encodable & Sendable>: Encodable, Sendable {
    var events: [Event]
    var scannedEvents: Int?
    var scanDepth: Int?
}
