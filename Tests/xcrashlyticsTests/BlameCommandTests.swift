//
//  BlameCommandTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore
import XCrashlyticsTestSupport
@testable import xcrashlytics

@Suite("xcrashlytics blame")
struct BlameCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("defaults are tuned for quick agent loops")
    func quickLoopDefaults() throws {
        let cmd = try BlameCommand.parse([])

        #expect(cmd.issueLimit == 30)
        #expect(cmd.eventsPerIssue == 1)
        #expect(cmd.concurrency == 6)
    }

    @Test("aggregates blamed frames across recent events")
    func aggregatesBlamedFrames() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let fs = try makeConfig()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try BlameCommand.parse([
            "--format", "json",
            "--top", "5",
            "--since", "7d",
            "--issue-limit", "2",
            "--events-per-issue", "2"
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(makeHTTP())
        )

        let env = try Envelope(output)
        let items = try #require(env.data["items"]?.array)
        // E-old (OldService) falls outside --since 7d, so only the shared Blur frame remains.
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item["file"]?.string == "BlurDetectionService.swift")
        #expect(item["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
        #expect(item["eventCount"]?.int == 2)
        #expect(item["users"]?.int == 2)
        #expect(item["exampleIssueId"]?.string == "FB-I1")
        let topIssueIds = Set(item["topIssueIds"]?.array?.compactMap(\.string) ?? [])
        #expect(topIssueIds == ["FB-I1", "FB-I2"])
        #expect(!items.contains { $0["symbol"]?.string == "OldService.crash()" })
    }

    @Test("ndjson emits one BlameSummary object per line")
    func ndjsonOutput() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let fs = try makeConfig()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try BlameCommand.parse([
            "--format", "ndjson",
            "--top", "5",
            "--since", "7d",
            "--issue-limit", "2",
            "--events-per-issue", "1"
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(makeMultiSymbolHTTP())
        )

        // Two distinct blamed symbols → two BlameSummary rows → two ndjson lines
        let lines = try JSON.lines(output)
        #expect(lines.count == 2)
        for line in lines {
            #expect(line["schemaVersion"]?.int == 1)
            #expect(line["eventCount"]?.int != nil)
        }
        let symbols = Set(lines.compactMap { $0["symbol"]?.string })
        #expect(symbols == ["BlurDetectionService.classifyWithML(_:)", "CameraPipeline.run()"])
    }

    /// Two issues, each blaming a distinct symbol — produces two BlameSummary rows.
    private func makeMultiSymbolHTTP() -> MockHTTPClient {
        MockHTTPClient { request in
            guard let url = request.url else {
                return MockHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                let body = #"""
                {"groups":[
                  {
                    "issue":{
                      "id":"I1",
                      "title":"[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
                      "errorType":"EXC_BAD_ACCESS",
                      "lastSeenVersion":"6.16.0"
                    },
                    "metrics":[{"eventsCount":"42","impactedUsersCount":"12"}]
                  },
                  {
                    "issue":{
                      "id":"I2",
                      "title":"[Core] CameraPipeline.swift - CameraPipeline.run()",
                      "errorType":"EXC_BAD_ACCESS",
                      "lastSeenVersion":"6.16.0"
                    },
                    "metrics":[{"eventsCount":"8","impactedUsersCount":"3"}]
                  }
                ]}
                """#
                return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            if url.query?.contains("filter.issue.id=I1") == true {
                let body = #"""
                {"events":[{
                  "eventId":"E1",
                  "eventTime":"2026-06-05T12:09:45Z",
                  "user":{"id":"U1"},
                  "threads":[{"crashed":true,"frames":[
                    {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
                  ]}]
                }]}
                """#
                return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
            }
            // I2 — different symbol so aggregation produces a second distinct row
            let body = #"""
            {"events":[{
              "eventId":"E2",
              "eventTime":"2026-06-06T12:09:45Z",
              "user":{"id":"U2"},
              "threads":[{"crashed":true,"frames":[
                {"symbol":"CameraPipeline.run()","library":"Core","file":"CameraPipeline.swift","line":"77","blamed":true}
              ]}]
            }]}
            """#
            return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
        }
    }

    private func makeConfig() throws -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        return fs
    }

    private func makeHTTP() -> MockHTTPClient {
        MockHTTPClient { request in
            guard let url = request.url else {
                return MockHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                #expect(url.query?.contains("page_size=2") == true)
                let body = #"""
                {"groups":[
                  {
                    "issue":{
                      "id":"I1",
                      "title":"[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                      "errorType":"EXC_BAD_ACCESS",
                      "lastSeenVersion":"6.16.0"
                    },
                    "metrics":[{"eventsCount":"42","impactedUsersCount":"12"}]
                  },
                  {
                    "issue":{
                      "id":"I2",
                      "title":"[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                      "errorType":"EXC_BAD_ACCESS",
                      "lastSeenVersion":"6.16.0"
                    },
                    "metrics":[{"eventsCount":"8","impactedUsersCount":"3"}]
                  }
                ]}
                """#
                return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            #expect(url.query?.contains("page_size=2") == true)
            if url.query?.contains("filter.issue.id=I1") == true {
                let body = #"""
                {"events":[
                  {
                    "eventId":"E1",
                    "eventTime":"2026-06-05T12:09:45Z",
                    "user":{"id":"U1"},
                    "threads":[{"crashed":true,"frames":[
                      {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
                    ]}]
                  },
                  {
                    "eventId":"E-old",
                    "eventTime":"2026-05-01T12:09:45Z",
                    "user":{"id":"U-old"},
                    "threads":[{"crashed":true,"frames":[
                      {"symbol":"OldService.crash()","library":"Core","file":"OldService.swift","line":"99","blamed":true}
                    ]}]
                  }
                ]}
                """#
                return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
            }
            let body = #"""
            {"events":[
              {
                "eventId":"E2",
                "eventTime":"2026-06-06T12:09:45Z",
                "user":{"id":"U2"},
                "blameFrame":{"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              }
            ]}
            """#
            return MockHTTPClient.response(url, status: 200, body: Data(body.utf8))
        }
    }
}
