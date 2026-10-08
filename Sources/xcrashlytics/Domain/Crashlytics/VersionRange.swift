import Foundation

struct VersionRange: Sendable, Equatable {
    var min: String
    var max: String

    // Orders by `AppVersion`, builds break ties; rows whose version does not parse are ignored.
    init?(_ rows: [BreakdownRow]) {
        let versions = rows.compactMap(Self.parsedVersion)
        guard let lowest = versions.min(by: Self.ordered), let highest = versions.max(by: Self.ordered) else {
            return nil
        }
        min = lowest.name
        max = highest.name
    }

    private struct ParsedVersion {
        let name: String
        let version: AppVersion
        let build: Int?
    }

    private static func parsedVersion(_ row: BreakdownRow) -> ParsedVersion? {
        guard row.eventsCount > 0, let display = row.displayVersion, let version = AppVersion(display) else {
            return nil
        }
        return ParsedVersion(name: row.name, version: version, build: row.buildVersion.flatMap { Int($0) })
    }

    private static func ordered(_ lhs: ParsedVersion, _ rhs: ParsedVersion) -> Bool {
        if lhs.version == rhs.version { return (lhs.build ?? 0) < (rhs.build ?? 0) }
        return lhs.version < rhs.version
    }
}
