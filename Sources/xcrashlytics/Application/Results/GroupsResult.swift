import Foundation

struct GroupsResult: Sendable {
    var window: DateInterval
    var groups: [CrashGroup]
    var warnings: [CommandWarning]
}
