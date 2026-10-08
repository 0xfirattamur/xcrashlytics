import Foundation

struct ReportedVersion: Sendable, Equatable {
    var displayVersion: String
    var buildVersion: String?
    // Crashlytics quirk: the API rejects a bare display version;
    // `filter.version.displayNames` takes e.g. `6.23.0 (1112)`.
    var displayName: String
}
