import Foundation

struct IssuesPayload: Encodable, Sendable {
    var query: String?
    var match: String?
    var limit: Int
    var searchLimit: Int
    var fetchedIssuesCount: Int
    var matchedIssuesCount: Int
    var hint: String?
    var appVersion: String?
    var sinceVersion: String?
    var matchedVersions: [String]?
    var file: String?
    var symbol: String?
    var since: String?
    var window: ReportWindowSummary
    var domain: String?
    var userInfoKey: [String]?
    var eventMetadataSamples: Int?
    var symbolicationHint: String?
    var issues: [IssueSummary]
    var xcodeCrashes: [XcodeIssueSummary]?
    var matchedXcodeCrashesCount: Int?
    var relatedGroups: [RelatedIssueGroupPayload]?

}
