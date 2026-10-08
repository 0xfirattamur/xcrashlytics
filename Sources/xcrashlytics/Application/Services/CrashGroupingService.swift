import Foundation

struct CrashGroupingService: Sendable {
    let sources: CrashSourceLoader
    let dateProvider: DateProvider

    func group(_ request: GroupsRequest) async throws -> GroupsResult {
        let window = try ReportWindow(since: request.since, now: dateProvider.currentDate()).interval
        let xcode = try loadXcode(request)
        var warnings = xcode.warnings

        let issues = try await loadFirebaseIssues(request, window: window, warnings: &warnings)

        var groups = CrashGrouper().group(local: xcode.crashes, firebase: issues)
        if let issue = request.issue {
            let targetId = CrashlyticsIdFormatter.canonicalIssueId(issue)
            groups = groups.filter { $0.firebase.contains { $0.id == targetId } }
            if groups.isEmpty {
                warnings.append(Self.issueNotFetchedWarning(
                    targetId: targetId, fetchedCount: issues.count, request: request))
            }
        }
        let displayedGroups = request.limit.map { Array(groups.prefix($0)) } ?? groups
        return GroupsResult(window: window, groups: displayedGroups, warnings: warnings)
    }

    private func loadXcode(_ request: GroupsRequest) throws -> XcodeCrashLoadResult {
        guard request.includesXcode else { return XcodeCrashLoadResult(crashes: [], warnings: []) }
        return try sources.xcodeCrashes(directories: request.crashDirectories)
    }

    private func loadFirebaseIssues(
        _ request: GroupsRequest, window: DateInterval, warnings: inout [CommandWarning]
    ) async throws -> [CrashIssue] {
        guard let client = try sources.firebaseClient(optional: request.includesXcode) else {
            warnings.append(CommandWarning(
                code: .firebaseSkipped,
                message: "No Firebase app is configured (run `xcrashlytics init`); "
                    + "showing local Xcode crashes only."))
            return []
        }
        return try await client.fetchIssues(
            limit: request.firebaseLimit, interval: window, options: IssueQueryOptions())
    }

    private static func issueNotFetchedWarning(
        targetId: String, fetchedCount: Int, request: GroupsRequest
    ) -> CommandWarning {
        let since = request.since ?? ReportWindow.defaultSince
        return CommandWarning(
            code: .issueNotInWindow,
            message: "\(targetId) is not among the \(fetchedCount) Firebase issues fetched "
                + "(top \(request.firebaseLimit), \(since)); "
                + "raise --firebase-limit or widen --since.")
    }
}
