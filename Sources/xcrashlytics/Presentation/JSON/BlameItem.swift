struct BlameItem: Encodable, Sendable {
    var file: String?
    var line: Int?
    var symbol: String?
    var binaryName: String?
    var eventCount: Int
    var users: Int
    var exampleIssueId: String
    var exampleEventId: String?
    var topIssueIds: [String]

    init(_ summary: BlameSummary) {
        file = summary.file
        line = summary.line
        symbol = summary.symbol
        binaryName = summary.binaryName
        eventCount = summary.eventCount
        users = summary.users
        exampleIssueId = summary.exampleIssueId
        exampleEventId = summary.exampleEventId
        topIssueIds = summary.topIssueIds
    }
}
