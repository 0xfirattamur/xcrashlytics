import Foundation

struct ReportWindowSummary: Encodable, Sendable, Equatable {
    var since: Date
    var until: Date

    init(_ interval: DateInterval) {
        since = interval.start
        until = interval.end
    }
}
