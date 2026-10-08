import Foundation

struct EventScanPlan: Sendable, Equatable {
    static let defaultLimit = 10
    static let userIdMinDepth = 50

    var requestedLimit: Int
    var userFiltered: Bool

    init(limit: Int?, latest: Bool, userFiltered: Bool) {
        requestedLimit = latest ? 1 : (limit ?? Self.defaultLimit)
        self.userFiltered = userFiltered
    }

    // `--user-id` is matched client-side, so scan at least 50 events inside the window.
    var depth: Int { userFiltered ? max(requestedLimit, Self.userIdMinDepth) : requestedLimit }

    var scansBeyondLimit: Bool { depth > requestedLimit }

    // Nil when fewer events than `depth` came back (the whole window was read); without
    // `--user-id` the server applies the window, so nothing can be missed.
    func truncationMessage(issueId: String, fetchedCount: Int) -> String? {
        guard userFiltered, fetchedCount >= depth else { return nil }
        return "\(issueId): scanned the newest \(depth) events in the window "
            + "without finding enough matches for --user-id; "
            + "older events in the window were not checked."
    }
}
