struct BlameRequest: Sendable {
    var top: Int
    var since: String
    var issueLimit: Int
    var eventsPerIssue: Int
    var concurrency: Int
}
