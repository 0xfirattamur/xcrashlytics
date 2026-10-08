import Foundation

struct IssueSearchResult: Sendable {
    var request: IssuesRequest
    var window: DateInterval
    var fetchLimit: Int
    var fetchedCount: Int
    var matchedCount: Int
    var issues: [CrashIssue]
    var eventMetadataSamples: Int
    /// Empty when no version of the window matched `--app-version`/`--since-version`.
    var matchedVersions: [String]?
    var lastSeenAt: [String: String]
    var xcodeCrashes: [XcodeCrash]
    var matchedXcodeCount: Int
    var hint: String?
    var symbolicationHint: String?
    var warnings: [CommandWarning]
}
