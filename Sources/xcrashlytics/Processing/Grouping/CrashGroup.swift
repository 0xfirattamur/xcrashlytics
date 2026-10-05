import Foundation

/// A cluster of same-culprit crashes — Firebase issues and local Xcode crashes
/// that share a `CrashSignature`. Collapses Firebase's over-splitting (one
/// function reported as several issues) and links it to local repros.
struct CrashGroup: Sendable, Equatable {
    /// Normalized culprit symbol; the group key.
    let symbol: String
    let module: String?
    let firebase: [CrashIssue]
    let xcode: [XcodeCrash]

    init(symbol: String, module: String?, firebase: [CrashIssue], xcode: [XcodeCrash]) {
        self.symbol = symbol
        self.module = module
        self.firebase = firebase
        self.xcode = xcode
    }

    /// Sum of known Firebase event counts; issues without a count are skipped.
    var totalEvents: Int { firebase.compactMap(\.eventsCount).reduce(0, +) }
    /// Sum of known impacted-user counts; issues without a count are skipped.
    var totalUsers: Int { firebase.compactMap(\.impactedUsersCount).reduce(0, +) }
    /// True when a local crash matches a Firebase issue.
    var isCrossSource: Bool { !firebase.isEmpty && !xcode.isEmpty }
}
