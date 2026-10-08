import Foundation

struct CrashExportResult {
    var detail: CrashDetail
    var spreads: CrashSpreads?
    var versionRange: VersionRange?
    var exportedAt: Date
    var window: DateInterval
    var warnings: [CommandWarning]
}

/// A dimension whose report failed is nil.
struct CrashSpreads {
    var window: DateInterval
    var versions: [BreakdownRow]?
    var operatingSystems: [BreakdownRow]?
    var devices: [BreakdownRow]?

    var isEmpty: Bool { versions == nil && operatingSystems == nil && devices == nil }
}
