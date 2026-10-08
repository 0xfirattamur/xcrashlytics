struct IssueReportTarget {
    var client: CrashlyticsClient
    /// Without the `FB-` prefix.
    var issueId: String

    static func resolve(_ id: String, clients: CrashlyticsClientProvider) throws -> IssueReportTarget {
        switch try CrashReference.parse(id, expecting: .firebaseIssue) {
        case let .consoleLink(link):
            return IssueReportTarget(client: try clients.client(for: link), issueId: link.issueId)
        case let .firebaseEvent(reference):
            return IssueReportTarget(client: try clients.client(), issueId: reference.issueId)
        case let .firebaseIssue(issueId):
            return IssueReportTarget(client: try clients.client(), issueId: issueId)
        case .xcodeCrash:
            preconditionFailure("CrashReference.Expectation.firebaseIssue never yields an Xcode crash")
        }
    }
}
