import Foundation

struct IssueEvents: Sendable {
    var issueId: String
    var events: [CrashlyticsEvent]
}
