import Foundation

struct CrashGroup: Sendable, Equatable {
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

    var totalEvents: Int { firebase.compactMap(\.eventsCount).reduce(0, +) }
    var totalUsers: Int { firebase.compactMap(\.impactedUsersCount).reduce(0, +) }
    var isCrossSource: Bool { !firebase.isEmpty && !xcode.isEmpty }
}
