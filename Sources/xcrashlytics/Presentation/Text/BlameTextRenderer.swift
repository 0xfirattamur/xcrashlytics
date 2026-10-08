struct BlameTextRenderer: Sendable {
    func render(_ rows: [BlameSummary]) -> String {
        guard !rows.isEmpty else {
            return "No blamed frames found.\n"
        }
        return rows.map(line).joined(separator: "\n") + "\n"
    }

    private func line(_ row: BlameSummary) -> String {
        let symbol = row.symbol ?? "?"
        let counts = "\(row.eventCount) events / \(row.users) users"
        return "\(counts)   \(location(of: row))   \(symbol)   \(row.exampleIssueId)"
    }

    private func location(of row: BlameSummary) -> String {
        guard let file = row.file else { return row.binaryName ?? "?" }
        guard let line = row.line else { return file }
        return "\(file):\(line)"
    }
}
