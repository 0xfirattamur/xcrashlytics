import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics issues")
struct IssuesCommandTests {
    let appId = "1:1234567890:ios:abcdef"

    @Test("filters issues by query, match, type, and minimum event count")
    func filtersIssues() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeMultiIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse([
            "blur",
            "--match", "BlurDetectionService",
            "--type", "EXC_BAD_ACCESS",
            "--min-events", "10",
            "--app-version", "6.16.0",
            "--file", "BlurDetectionService.swift",
            "--symbol", "BlurDetectionService.classifyWithML(_:)",
            "--format", "json",
            "--limit", "200",
        ])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I1"))
        #expect(!ids.contains("FB-I2"))
        #expect(!ids.contains("FB-I3"))
        #expect(env.data["issues"]?[0]?["title"]?.string?.contains("BlurDetectionService") == true)
        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true })
        #expect(TopVersionsFixture.displayNames(of: topIssues) == ["6.16.0 (937)"])
    }

    @Test("--since is the server report window, not a per-issue event filter")
    func sinceIsServerWindow() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let fileStore = try makeConfig()
        let httpClient = makeMultiIssuesWithEventsHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(now)
        )
        let cmd = try IssuesCommand.parse([
            "--since", "24h",
            "--format", "json",
            "--limit", "200",
        ])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids == ["FB-I1", "FB-I2", "FB-I3"])
        #expect(env.data["window"]?["since"]?.string == "2026-06-07T00:00:00Z")
        #expect(env.data["window"]?["until"]?.string == "2026-06-08T00:00:00Z")
        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url)
        #expect(topIssues.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-07T00:00:00Z")
        #expect(topIssues.issuesQueryItem(named: "filter.interval.endTime") == "2026-06-08T00:00:00Z")
        // Only the last-seen decoration reads events: one request per displayed issue, none to filter by --since.
        #expect(httpClient.requests.filter { $0.url?.path.hasSuffix("/events") == true }.count == 3)
    }

    @Test("query auto widens fetch window while limit controls displayed matches")
    func queryAutoWidensFetchWindow() async throws {
        let fileStore = try makeConfig()
        var requestedPageSize: String?
        let httpClient = makeRankedIssuesHTTP(matchIndex: 70, total: 70) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["blur", "--format", "json", "--limit", "1"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        #expect(requestedPageSize == "100")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.compactMap { $0["id"]?.string } == ["FB-I70"])
        #expect(env.data["limit"]?.int == 1)
        #expect(env.data["searchLimit"]?.int == 200)
    }

    @Test("search-limit overrides the query fetch window")
    func searchLimitOverridesFetchWindow() async throws {
        let fileStore = try makeConfig()
        var requestedPageSize: String?
        let httpClient = makeRankedIssuesHTTP(matchIndex: 40, total: 40) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["blur", "--search-limit", "50", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        #expect(requestedPageSize == "50")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-I40" } == true)
        #expect(env.data["searchLimit"]?.int == 50)
    }

    @Test("empty filtered result includes an anti-silent-miss hint")
    func emptyFilteredResultIncludesHint() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeRankedIssuesHTTP(matchIndex: nil, total: 20)
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["missing", "--search-limit", "20", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.isEmpty == true)
        #expect(env.data["hint"]?.string == "0 matches in top 20 by impact. Rerun with --search-limit 500.")
    }

    @Test("empty result does not suggest widening when fetched issues are exhausted")
    func emptyResultExhaustedHint() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeRankedIssuesHTTP(matchIndex: nil, total: 2)
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["missing", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["hint"]?.string == "0 matches in all 2 fetched issues.")
    }

    @Test("all searches use the capped exhaustive fetch limit")
    func allUsesCappedFetchLimit() async throws {
        let fileStore = try makeConfig()
        var requestedPageSize: String?
        let httpClient = makeRankedIssuesHTTP(matchIndex: 120, total: 120) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["blur", "--all", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        #expect(requestedPageSize == "100")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-I120" } == true)
        #expect(env.data["searchLimit"]?.int == 2000)
    }

    @Test("includes Xcode crashes when requested")
    func includesXcodeCrashes() async throws {
        let httpClient = makeIssuesHTTP()
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        let crashDir = "/crashes"
        fileStore.seed("\(crashDir)/A.crash", text: try XcodeFixtures.text("sample.crash"))
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["--xcode", "--crash-directory", crashDir, "--format", "json"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        let xcodeIds = env.data["xcodeCrashes"]?.array?.compactMap { $0["id"]?.string }
        #expect(xcodeIds == ["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])
    }
}
