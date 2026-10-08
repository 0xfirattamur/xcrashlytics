import Foundation

/// A Firebase issue's totals over an explicit window as Crashlytics reports them, not a sample.
struct IssueImpact: Sendable, Equatable {
    var since: Date
    var until: Date
    var eventsCount: Int
    var impactedUsersCount: Int
    var appUsersCount: Int?

    var impactedUsersPercentage: Double? {
        guard let appUsersCount, appUsersCount > 0 else { return nil }
        return Double(impactedUsersCount) / Double(appUsersCount) * 100
    }
}
