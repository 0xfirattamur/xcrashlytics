struct BlamePayload: Encodable, Sendable {
    var since: String
    var issueLimit: Int
    var eventsPerIssue: Int
    var concurrency: Int
    var items: [BlameSummary]

}

// MARK: - BlameRenderer

enum BlameRenderer {
    static func text(_ rows: [BlameSummary]) -> String {
        guard !rows.isEmpty else {
            return "No blamed frames found.\n"
        }
        return rows.map { row in
            let location = row.file.map { file in
                row.line.map { "\(file):\($0)" } ?? file
            } ?? row.binaryName ?? "?"
            let symbol = row.symbol ?? "?"
            return "\(row.eventCount) events / \(row.users) users   \(location)   \(symbol)   \(row.exampleIssueId)"
        }.joined(separator: "\n") + "\n"
    }

    static func json(_ payload: BlamePayload) throws -> String {
        try PayloadEncoder.envelope(payload, warnings: [])
    }

    static func ndjson(_ rows: [BlameSummary]) throws -> String {
        try PayloadEncoder.ndjson(rows)
    }
}
