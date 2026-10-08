struct GroupRecord: Encodable, Sendable {
    let symbol: String
    let module: String?
    let crossSource: Bool
    let totalEvents: Int
    let totalUsers: Int
    let firebase: [GroupedIssueRecord]
    let xcode: [GroupedXcodeCrashRecord]

    init(_ group: CrashGroup) {
        symbol = group.symbol
        module = group.module
        crossSource = group.isCrossSource
        totalEvents = group.totalEvents
        totalUsers = group.totalUsers
        firebase = group.firebase.map(GroupedIssueRecord.init)
        xcode = group.xcode.map(GroupedXcodeCrashRecord.init)
    }
}
