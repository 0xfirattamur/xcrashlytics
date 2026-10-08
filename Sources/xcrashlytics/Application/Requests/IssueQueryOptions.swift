import Foundation

struct IssueQueryOptions: Sendable, Equatable {
    var includesDailyCounts = false
    // Crashlytics quirk: entries must be full display names (`6.23.0 (1112)`); a bare version is rejected.
    var versionDisplayNames: [String] = []
}
