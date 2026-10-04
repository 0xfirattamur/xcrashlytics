import Foundation
import Testing
@testable import XCrashlyticsCore
import XCrashlyticsTestSupport
@testable import xcrashlytics

@Suite("xcrashlytics issues")
struct IssuesCommandTests {
    let appId = "1:1234567890:ios:abcdef"

    @Test("renders compact JSON from live Firebase")
    func rendersJSON() async throws {
        let fs = try makeConfig()
        let http = makeIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        let env = try Envelope(output)
        let issue = try #require(env.data["issues"]?[0])
        #expect(issue["id"]?.string == "FB-I1")
        #expect(issue["title"]?.string == "Crash in Checkout")
        #expect(issue["eventsCount"]?.int == 42)
        #expect(issue["impactedUsersCount"]?.int == 12)
        #expect(issue["rawJSON"] == nil)
    }

    @Test("renders compact text from live Firebase")
    func rendersText() async throws {
        let fs = try makeConfig()
        let http = makeIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        #expect(output.contains("FB-I1"))
        #expect(output.contains("42 events / 12 users"))
        #expect(output.contains("Crash in Checkout"))
    }

    @Test("filters issues by query, match, type, and minimum event count")
    func filtersIssues() async throws {
        let fs = try makeConfig()
        let http = makeMultiIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
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

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I1"))
        #expect(!ids.contains("FB-I2"))
        #expect(!ids.contains("FB-I3"))
        #expect(env.data["issues"]?[0]?["title"]?.string?.contains("BlurDetectionService") == true)
    }

    @Test("filters issues by latest event time when since is provided")
    func filtersIssuesBySince() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let fs = try makeConfig()
        let http = makeMultiIssuesWithEventsHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try IssuesCommand.parse([
            "--since", "24h",
            "--format", "json",
            "--limit", "200",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I1"))
        #expect(!ids.contains("FB-I2"))
        #expect(!ids.contains("FB-I3"))
    }

    @Test("query auto widens fetch window while limit controls displayed matches")
    func queryAutoWidensFetchWindow() async throws {
        let fs = try makeConfig()
        var requestedPageSize: String?
        let http = makeRankedIssuesHTTP(matchIndex: 70, total: 70) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--format", "json", "--limit", "1"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        #expect(requestedPageSize == "100")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.compactMap { $0["id"]?.string } == ["FB-I70"])
        #expect(env.data["limit"]?.int == 1)
        #expect(env.data["searchLimit"]?.int == 200)
    }

    @Test("search-limit overrides the query fetch window")
    func searchLimitOverridesFetchWindow() async throws {
        let fs = try makeConfig()
        var requestedPageSize: String?
        let http = makeRankedIssuesHTTP(matchIndex: 40, total: 40) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--search-limit", "50", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        #expect(requestedPageSize == "50")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-I40" } == true)
        #expect(env.data["searchLimit"]?.int == 50)
    }

    @Test("empty filtered result includes an anti-silent-miss hint")
    func emptyFilteredResultIncludesHint() async throws {
        let fs = try makeConfig()
        let http = makeRankedIssuesHTTP(matchIndex: nil, total: 20)
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["missing", "--search-limit", "20", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.isEmpty == true)
        #expect(env.data["hint"]?.string == "0 matches in top 20 by impact. Rerun with --search-limit 500.")
    }

    @Test("empty result does not suggest widening when fetched issues are exhausted")
    func emptyResultExhaustedHint() async throws {
        let fs = try makeConfig()
        let http = makeRankedIssuesHTTP(matchIndex: nil, total: 2)
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["missing", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        let env = try Envelope(output)
        #expect(env.data["hint"]?.string == "0 matches in all 2 fetched issues.")
    }

    @Test("all searches use the capped exhaustive fetch limit")
    func allUsesCappedFetchLimit() async throws {
        let fs = try makeConfig()
        var requestedPageSize: String?
        let http = makeRankedIssuesHTTP(matchIndex: 120, total: 120) { request in
            if request.url?.path.hasSuffix("/reports/topIssues") == true {
                requestedPageSize = request.url?.issuesQueryItem(named: "page_size")
            }
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--all", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
            )

        #expect(requestedPageSize == "100")
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-I120" } == true)
        #expect(env.data["searchLimit"]?.int == 2000)
    }

    @Test("agent JSON uses compact related groups without candidate pairs")
    func relatedGroupsReplaceCandidatePairs() async throws {
        let fs = try makeMultiIssuesHTTPConfig()
        let http = makeMultiIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--format", "json", "--limit", "200"])
        let output = try await cmd.runWithContext(ctx.withFirebaseHTTP(http))
        let env = try Envelope(output)
        #expect(env.data["issues"]?.array != nil)
        #expect(env.data["relatedGroups"]?.array?.isEmpty == false)
        #expect(env.data["candidatePairs"] == nil)
    }

    @Test("includes Xcode crashes when requested")
    func includesXcodeCrashes() async throws {
        let http = makeIssuesHTTP()
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        let crashDir = "/crashes"
        fs.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["--xcode", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http),
            crashDirectories: [crashDir]
        )

        let env = try Envelope(output)
        let xcodeIds = env.data["xcodeCrashes"]?.array?.compactMap { $0["id"]?.string }
        #expect(xcodeIds == ["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])
    }
}
