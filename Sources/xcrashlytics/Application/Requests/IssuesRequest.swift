struct IssuesRequest: Sendable {
    var criteria: IssueCriteria
    var limit: Int
    var searchLimit: Int?
    var all: Bool
    var since: String?
    var byDay: Bool
    var eventsPerIssue: Int?
    var includesXcode: Bool
    var crashDirectories: [String]

    init(
        criteria: IssueCriteria, limit: Int, searchLimit: Int?, all: Bool, since: String?, byDay: Bool,
        eventsPerIssue: Int?, xcode: Bool, crashDirectories: [String]
    ) {
        self.criteria = criteria
        self.limit = limit
        self.searchLimit = searchLimit
        self.all = all
        self.since = since
        self.byDay = byDay
        self.eventsPerIssue = eventsPerIssue
        self.crashDirectories = crashDirectories
        includesXcode = xcode || !crashDirectories.isEmpty
    }
}
