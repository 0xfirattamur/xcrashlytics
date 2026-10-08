import Foundation

struct IssuesTextRenderer: Sendable {
    private static let columnSeparator = "   "

    func render(
        issues: [CrashIssue],
        xcodeCrashes: [XcodeCrash],
        hint: String?,
        symbolicationHint: String?,
        lastSeenAt: [String: String] = [:]
    ) -> String {
        guard !issues.isEmpty || !xcodeCrashes.isEmpty else {
            return emptyResult(hint: hint, symbolicationHint: symbolicationHint)
        }
        let issueRows = issues.map { issueRow($0, lastSeenAt: lastSeenAt[$0.id]) }
        let crashRows = xcodeCrashes.map(xcodeCrashRow)
        return (issueRows + crashRows).joined(separator: "\n") + "\n"
    }

    // MARK: - Rows

    private func emptyResult(hint: String?, symbolicationHint: String?) -> String {
        var lines = ["No Firebase issues found."]
        if let hint {
            lines.append("Hint: \(hint)")
        }
        if let symbolicationHint {
            lines.append("Symbolication: \(symbolicationHint)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func issueRow(_ issue: CrashIssue, lastSeenAt: String?) -> String {
        let events = issue.eventsCount.map(String.init) ?? "?"
        let users = issue.impactedUsersCount.map(String.init) ?? "?"
        let columns = [
            issue.id,
            issue.exception.exceptionType,
            versionDescription(issue),
            issue.exception.description ?? "-",
            "\(events) events / \(users) users"
        ]
        let row = columns.joined(separator: Self.columnSeparator)
        return row + lastEventDescription(lastSeenAt) + trendDescription(issue)
    }

    private func xcodeCrashRow(_ crash: XcodeCrash) -> String {
        let event = crash.event
        let columns = [event.id, event.bundleVersion ?? "unknown app", event.exception.exceptionType]
        return columns.joined(separator: Self.columnSeparator)
    }

    // MARK: - Row fragments

    private func versionDescription(_ issue: CrashIssue) -> String {
        IssueSeenVersions.description(first: issue.firstSeenVersion, last: issue.lastSeenVersion) ?? "-"
    }

    private func lastEventDescription(_ lastSeenAt: String?) -> String {
        guard let lastSeenAt else { return "" }
        let day = EventTimestampParser.dayString(from: lastSeenAt) ?? lastSeenAt
        return Self.columnSeparator + "last event \(day)"
    }

    private func trendDescription(_ issue: CrashIssue) -> String {
        guard let days = issue.dailyEvents, !days.isEmpty else { return "" }
        return Self.columnSeparator + days.map { "\($0.day):\($0.eventsCount)" }.joined(separator: ",")
    }
}
