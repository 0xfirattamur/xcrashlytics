import Foundation

struct IssueDisplaySignature: Sendable, Equatable {
    var module: String?
    var file: String?
    var symbol: String?

    init?(_ issue: CrashIssue) {
        guard let title = IssueTitle(issue.exception.description) else { return nil }
        module = title.module
        guard !title.namesCrashlyticsSDK else { return }
        file = title.file
        symbol = title.symbol
    }
}
