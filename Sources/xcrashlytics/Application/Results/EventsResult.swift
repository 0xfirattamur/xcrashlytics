import Foundation

struct EventsResult: Sendable {
    var request: EventsRequest
    var issueEvents: [IssueEvents]
    var scan: Scan?
    var warnings: [CommandWarning]
    var frameSelector: FrameSelector

    struct Scan: Sendable, Equatable {
        var scannedEvents: Int
        var depth: Int
    }
}
