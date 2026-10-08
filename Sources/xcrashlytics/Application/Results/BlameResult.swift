import Foundation

struct BlameResult: Sendable {
    var request: BlameRequest
    var window: DateInterval
    var issuesScanned: Int
    var sampledEvents: Int
    var rows: [BlameSummary]
}
