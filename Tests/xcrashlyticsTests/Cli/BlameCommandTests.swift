import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics blame")
struct BlameCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("aggregates blamed frames across recent events")
    func aggregatesBlamedFrames() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let fileStore = try makeConfig()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(now)
        )
        let cmd = try BlameCommand.parse([
            "--format", "json",
            "--top", "5",
            "--since", "7d",
            "--issue-limit", "2",
            "--events-per-issue", "2"
        ])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(makeHTTP())
        .container)

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

    @Test("ties rank deterministically by file, symbol, line, then library")
    func deterministicTieOrder() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let cmd = try BlameCommand.parse(["--format", "json", "--issue-limit", "4", "--top", "10"])
        var orders: Set<[Int]> = []
        for _ in 0..<5 {
            let ctx = Platform.testing(
                fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
            let output = try await cmd.execute(ctx.withFirebaseHTTP(makeSameFrameDifferentLineHTTP()).container)
            let lines = try Envelope(output).data["items"]?.array?.compactMap { $0["line"]?.int } ?? []
            orders.insert(lines)
        }
        #expect(orders == [[10, 20, 30, 40]])
    }

    @Test("a missing blame frame falls back to the first app frame, not a system frame")
    func blameFallbackSkipsSystemFrames() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
        let httpClient = FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"groups":[{"issue":{"id":"I1","title":"t","errorType":"FATAL"},"metrics":[{"eventsCount":"1"}]}]}
                """#.utf8))
            }
            return FakeHTTPClient.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E1","eventTime":"2026-06-07T12:00:00Z","threads":[{"crashed":true,"frames":[
              {"symbol":"<redacted>","library":"libsystem_kernel.dylib","owner":"SYSTEM"},
              {"symbol":"Checkout.pay()","library":"Core","file":"Checkout.swift","line":"9","owner":"APPLICATION"}
            ]}]}]}
            """#.utf8))
        }

        let output = try await BlameCommand.parse(["--format", "json"]).execute(ctx.withFirebaseHTTP(httpClient).container)

        #expect(try Envelope(output).data["items"]?[0]?["symbol"]?.string == "Checkout.pay()")
    }

    @Test("sends the report window, reports it with effective settings, and rejects bad input before any request")
    func windowAndEchoes() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let httpClient = makeMultiSymbolHTTP()
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
        let output = try await BlameCommand.parse(["--format", "json", "--since", "48h", "--issue-limit", "2", "--top", "1"])
            .execute(ctx.withFirebaseHTTP(httpClient).container)

        let data = try Envelope(output).data
        #expect(data["window"]?["since"]?.string == "2026-06-06T00:00:00Z")
        #expect(data["window"]?["until"]?.string == "2026-06-08T00:00:00Z")
        #expect(data["top"]?.int == 1)
        #expect(data["issuesScanned"]?.int == 2)
        #expect(data["sampledEvents"]?.int == 1)  // E1 (06-05) falls before the 48h cutoff; E2 (06-06 12:09) is inside
        #expect(data["items"]?.array?.count == 1)
        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url)
        #expect(topIssues.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-06T00:00:00Z")

        let strict = FakeHTTPClient { _ in throw HTTPTransportError.transport("no request expected") }
        for args in [["--since", "91d"], ["--since", "0d"], ["--issue-limit", "0"], ["--top", "0"],
                     ["--events-per-issue=-1"], ["--concurrency", "0"]] {
            let bad = try BlameCommand.parse(["--format", "json"] + args)
            do {
                _ = try await bad.execute(ctx.withFirebaseHTTP(strict).container)
                Issue.record("expected BAD_INPUT for \(args)")
            } catch {
                #expect(CommandRunner.failure(for: error).code == "BAD_INPUT", "\(args)")
            }
        }
        #expect(strict.requests.isEmpty)
    }

    private func makeSameFrameDifferentLineHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/reports/topIssues") {
                let groups = (1...4).map { #"{"issue":{"id":"I\#($0)","title":"t","errorType":"FATAL"},"metrics":[{"eventsCount":"1"}]}"# }
                return FakeHTTPClient.response(url, status: 200, body: Data("{\"groups\":[\(groups.joined(separator: ","))]}".utf8))
            }
            let issue = url.query?.components(separatedBy: "filter.issue.id=").last?.prefix(2).dropFirst() ?? "1"
            let line = (Int(issue) ?? 1) * 10
            return FakeHTTPClient.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E","eventTime":"2026-06-07T12:00:00Z","blameFrame":
              {"symbol":"Same.run()","library":"Core","file":"Same.swift","line":"\#(line)","blamed":true}}]}
            """#.utf8))
        }
    }

    /// Two issues, each blaming a distinct symbol — produces two BlameSummary rows.
    private func makeMultiSymbolHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
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
                return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
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
                return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
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
            return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
        }
    }

    private func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    private func makeHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
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
                return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
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
                return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
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
            return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
        }
    }
}
