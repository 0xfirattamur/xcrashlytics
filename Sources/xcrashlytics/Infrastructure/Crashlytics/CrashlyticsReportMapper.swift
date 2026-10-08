import Foundation

struct CrashlyticsReportMapper: Sendable {
    func reportedVersion(from dto: CrashlyticsDTO.Version) -> ReportedVersion? {
        guard let display = dto.displayVersion?.trimmedNonEmpty ?? dto.displayName?.trimmedNonEmpty else { return nil }
        let build = dto.buildVersion?.trimmedNonEmpty
        return ReportedVersion(
            displayVersion: display,
            buildVersion: build,
            displayName: dto.displayName?.trimmedNonEmpty ?? build.map { "\(display) (\($0))" } ?? display)
    }

    // Crashlytics quirk: with a granularity the first point is the whole window and the rest
    // are one per day, so it is dropped. Points repeating a start time count once.
    func dailyEvents(from metrics: [CrashlyticsDTO.IssueReportMetrics]) -> [DailyEventCount] {
        var starts: Set<String> = []
        var perDay: [String: Int] = [:]
        for point in metrics.dropFirst() {
            guard let start = point.startTime, start.count >= 10, starts.insert(start).inserted else { continue }
            perDay[String(start.prefix(10)), default: 0] += point.eventsCount?.intValue ?? 0
        }
        return perDay
            .filter { $0.value > 0 }
            .map { DailyEventCount(day: $0.key, eventsCount: $0.value) }
            .sorted { $0.day < $1.day }
    }

    // Device reports nest models as `subgroups`; a childless device group stands for itself.
    func breakdownRows(
        from group: CrashlyticsDTO.BreakdownReportGroup, dimension: BreakdownDimension, issueScoped: Bool
    ) -> [BreakdownRow] {
        switch dimension {
        case .version:
            guard let reported = group.version.flatMap(reportedVersion(from:)) else { return [] }
            return [versionRow(reported, group: group, issueScoped: issueScoped)]
        case .os:
            return osRow(group, issueScoped: issueScoped).map { [$0] } ?? []
        case .device:
            guard !group.subgroups.isEmpty else {
                return deviceRow(group, issueScoped: issueScoped).map { [$0] } ?? []
            }
            return group.subgroups.compactMap { deviceRow($0, issueScoped: issueScoped) }
        }
    }

    func ranked(_ rows: [BreakdownRow]) -> [BreakdownRow] {
        var rows = rows.filter { $0.eventsCount > 0 }
        let total = rows.reduce(0) { $0 + $1.eventsCount }
        rows.sort { ($1.eventsCount, $0.name) < ($0.eventsCount, $1.name) }
        for index in rows.indices {
            rows[index].eventsShare = Double(rows[index].eventsCount) * 100 / Double(total)
        }
        return rows
    }

    private func baseRow(
        _ dimension: BreakdownDimension, name: String, group: CrashlyticsDTO.BreakdownReportGroup
    ) -> BreakdownRow {
        let metrics = group.windowMetrics
        return BreakdownRow(
            dimension: dimension,
            name: name,
            eventsCount: metrics?.eventsCount?.intValue ?? 0,
            impactedUsersCount: metrics?.impactedUsersCount?.intValue ?? 0,
            sessionsCount: metrics?.sessionsCount?.intValue)
    }

    private func versionRow(
        _ reported: ReportedVersion, group: CrashlyticsDTO.BreakdownReportGroup, issueScoped: Bool
    ) -> BreakdownRow {
        var row = baseRow(.version, name: reported.displayName, group: group)
        row.displayVersion = reported.displayVersion
        row.buildVersion = reported.buildVersion
        row.versionUsersCount = group.windowMetrics?.totalUsersCount?.intValue
        if issueScoped {
            if let users = row.versionUsersCount, users > 0 {
                row.impactedUsersPercentage = Double(row.impactedUsersCount) * 100 / Double(users)
            }
        } else {
            row.totalSessionsCount = group.windowMetrics?.totalSessionsCount?.intValue
            row.crashFreeUsersPercentage = group.windowMetrics?.crashFreeUsersPercentage
        }
        return row
    }

    private func osRow(_ group: CrashlyticsDTO.BreakdownReportGroup, issueScoped: Bool) -> BreakdownRow? {
        guard let system = group.operatingSystem else { return nil }
        let version = system.displayVersion?.trimmedNonEmpty
        let fallbackName = Self.joinedName(system.os?.trimmedNonEmpty, version.map { "(\($0))" })
        guard let name = system.displayName?.trimmedNonEmpty ?? fallbackName else { return nil }
        var row = baseRow(.os, name: name, group: group)
        row.os = system.os?.trimmedNonEmpty
        row.osVersion = version
        if !issueScoped { applyPopulation(to: &row, group: group) }
        return row
    }

    private func deviceRow(_ group: CrashlyticsDTO.BreakdownReportGroup, issueScoped: Bool) -> BreakdownRow? {
        guard let device = group.device else { return nil }
        let model = device.model?.trimmedNonEmpty
        let manufacturer = device.manufacturer?.trimmedNonEmpty
        let fallbackName = Self.joinedName(manufacturer, model.map { "(\($0))" })
        guard let name = device.displayName?.trimmedNonEmpty ?? fallbackName else { return nil }
        var row = baseRow(.device, name: name, group: group)
        row.manufacturer = manufacturer
        row.model = model
        row.marketingName = device.marketingName?.trimmedNonEmpty
        if !issueScoped { applyPopulation(to: &row, group: group) }
        return row
    }

    private static func joinedName(_ parts: String?...) -> String? {
        parts.compactMap { $0 }.joined(separator: " ").trimmedNonEmpty
    }

    // Crashlytics quirk: with an issue filter `totalUsersCount` of OS/device reports is not a
    // population. Unfiltered rows carry a crash-free percentage with a real population, or omit both.
    private func applyPopulation(to row: inout BreakdownRow, group: CrashlyticsDTO.BreakdownReportGroup) {
        guard let percentage = group.windowMetrics?.crashFreeUsersPercentage else { return }
        row.usersCount = group.windowMetrics?.totalUsersCount?.intValue
        row.totalSessionsCount = group.windowMetrics?.totalSessionsCount?.intValue
        row.crashFreeUsersPercentage = percentage
    }
}
