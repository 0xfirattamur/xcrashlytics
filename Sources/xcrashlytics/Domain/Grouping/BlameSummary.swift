struct BlameSummary: Sendable {
    var file: String?
    var line: Int?
    var symbol: String?
    var binaryName: String?
    var eventCount: Int
    var users: Int
    var exampleIssueId: String
    var exampleEventId: String?
    var topIssueIds: [String]
}
