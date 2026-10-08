import Foundation

struct BreakdownRow: Sendable, Equatable {
    var dimension: BreakdownDimension
    /// `4.0.1 (106)`, `iOS (27.2.0)`, `Apple (iPhone18,2)`.
    var name: String
    var displayVersion: String?
    var buildVersion: String?
    var os: String?
    var osVersion: String?
    var manufacturer: String?
    var model: String?
    var marketingName: String?
    var eventsCount: Int
    var impactedUsersCount: Int
    /// Percent (0–100) of the report's events in this group.
    var eventsShare: Double?
    var sessionsCount: Int?
    /// Versions only: all users of that version in the window, whatever they hit.
    var versionUsersCount: Int?
    /// Issue version breakdown: impacted users as a percent of `versionUsersCount`.
    var impactedUsersPercentage: Double?
    // Crashlytics quirk: app-wide OS/device rows carry a user population only sometimes,
    // and then also a crash-free percentage.
    var usersCount: Int?
    var totalSessionsCount: Int?
    var crashFreeUsersPercentage: Double?
}
