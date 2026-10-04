//
//  BlameOutput.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import XCrashlyticsCore

public struct BlamePayload: Encodable, Sendable {
    public var since: String
    public var issueLimit: Int
    public var eventsPerIssue: Int
    public var concurrency: Int
    public var items: [BlameSummary]

    public init(
        since: String,
        issueLimit: Int,
        eventsPerIssue: Int,
        concurrency: Int,
        items: [BlameSummary]
    ) {
        self.since = since
        self.issueLimit = issueLimit
        self.eventsPerIssue = eventsPerIssue
        self.concurrency = concurrency
        self.items = items
    }
}

// MARK: - BlameRenderer

public enum BlameRenderer {
    public static func text(_ rows: [BlameSummary]) -> String {
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
