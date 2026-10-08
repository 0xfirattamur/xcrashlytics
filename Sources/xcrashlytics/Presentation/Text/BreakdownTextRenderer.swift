import Foundation

struct BreakdownTextRenderer: Sendable {
    private struct Column {
        var header: String
        var cell: (BreakdownRow) -> String?
        var isLeftAligned = false
        var isAlwaysShown = false
    }

    private static let columnSeparator = "  "
    private static let missingCell = "-"

    private let dayFormatter = UTCDateFormatter.make(UTCDateFormatter.dayFormat)

    // MARK: - Rendering

    func render(_ result: BreakdownResult) -> String {
        var lines = [summaryLine(result)]
        if let range = result.versionRange {
            lines.append("Versions with events: \(range.min) … \(range.max).")
        }
        if result.rows.isEmpty {
            lines.append("No events in the window.")
        } else {
            lines.append("")
            lines += tableLines(result.rows)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func summaryLine(_ result: BreakdownResult) -> String {
        let subject = result.issueId.map { "of \($0)" } ?? "app-wide"
        let since = dayFormatter.string(from: result.window.start)
        let until = dayFormatter.string(from: result.window.end)
        let groups = result.groupCount == 1 ? "group" : "groups"
        return "Events by \(label(result.dimension)) \(subject), \(since) → \(until): "
            + "\(result.eventsCount) events in \(result.groupCount) \(groups)."
    }

    private func label(_ dimension: BreakdownDimension) -> String {
        switch dimension {
        case .version: return "app version"
        case .os: return "OS version"
        case .device: return "device model"
        }
    }

    // MARK: - Table

    /// Optional columns are dropped when no row has a value for them.
    private func columns(for rows: [BreakdownRow]) -> [Column] {
        allColumns.filter { column in
            column.isAlwaysShown || rows.contains { column.cell($0) != nil }
        }
    }

    private var allColumns: [Column] {
        [
            Column(header: "NAME", cell: nameCell, isLeftAligned: true, isAlwaysShown: true),
            Column(header: "EVENTS", cell: { String($0.eventsCount) }),
            Column(header: "SHARE", cell: { $0.eventsShare.map(percent) }),
            Column(header: "USERS", cell: { String($0.impactedUsersCount) }),
            Column(header: "VERSION USERS", cell: { $0.versionUsersCount.map(String.init) }),
            Column(header: "USERS HIT", cell: { $0.impactedUsersPercentage.map(percent) }),
            Column(header: "ALL USERS", cell: { $0.usersCount.map(String.init) }),
            Column(header: "CRASH-FREE", cell: { $0.crashFreeUsersPercentage.map(percent) }),
            Column(header: "SESSIONS", cell: { $0.sessionsCount.map(String.init) })
        ]
    }

    private func nameCell(_ row: BreakdownRow) -> String? {
        row.marketingName.map { "\(row.name) \($0)" } ?? row.name
    }

    private func tableLines(_ rows: [BreakdownRow]) -> [String] {
        let columns = columns(for: rows)
        let cellRows = rows.map { row in columns.map { $0.cell(row) ?? Self.missingCell } }
        let widths = columnWidths(columns, cellRows: cellRows)
        let header = columns.map(\.header)
        return ([header] + cellRows).map { line(for: $0, columns: columns, widths: widths) }
    }

    private func columnWidths(_ columns: [Column], cellRows: [[String]]) -> [Int] {
        columns.indices.map { index in
            let widestCell = cellRows.map { $0[index].count }.max() ?? 0
            return max(columns[index].header.count, widestCell)
        }
    }

    private func line(for cells: [String], columns: [Column], widths: [Int]) -> String {
        let aligned = columns.indices.map { index in
            let padding = String(repeating: " ", count: widths[index] - cells[index].count)
            return columns[index].isLeftAligned ? cells[index] + padding : padding + cells[index]
        }
        return aligned.joined(separator: Self.columnSeparator).trimmingTrailingWhitespace()
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }
}
