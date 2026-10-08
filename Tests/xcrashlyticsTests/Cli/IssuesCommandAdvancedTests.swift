import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    @Test("query searches latest event metadata when issue fields do not match")
    func querySearchesEventMetadata() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeMetricKitHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse([
            "com.metrickit.diagnostics.cpu",
            "--format", "json",
        ])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-MX" } == true)
        #expect(env.data["eventMetadataSamples"]?.int == 1)
    }

    @Test("filters issues by event domain and userInfo key")
    func filtersByEventDomainAndUserInfo() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeMetricKitHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse([
            "--domain", "com.metrickit.diagnostics.cpu",
            "--user-info-key", "reason=cpu spike",
            "--format", "json",
        ])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-MX"))
        #expect(!ids.contains("FB-OTHER"))
    }

    @Test("filters issues by raw Firebase user id across sampled events")
    func filtersIssuesByUserId() async throws {
        let fileStore = try makeConfig()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse([
            "--user-id", "target-user",
            "--events-per-issue", "2",
            "--format", "json",
        ])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(makeUserIssuesHTTP()).container)

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I1"))
        #expect(!ids.contains("FB-I2"))
        #expect(!output.contains("target-user"))
    }

    @Test("filters Xcode crashes using the same issue criteria")
    func filtersXcodeCrashesWithIssueCriteria() async throws {
        let httpClient = makeRankedIssuesHTTP(matchIndex: nil, total: 2)
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        let crashDir = "/crashes"
        fileStore.seed("\(crashDir)/A.crash", text: try XcodeFixtures.text("sample.crash"))
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse(["missing", "--xcode", "--crash-directory", crashDir, "--format", "json"])
        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)
        let env = try Envelope(output)
        // sample.crash does not match "missing", so the Xcode list is present but filtered empty.
        #expect(env.data["xcodeCrashes"]?.array?.isEmpty == true)
        #expect(env.data["symbolicationHint"] == nil)
    }

    @Test("since all is the 90-day window, and since-version restricts the report's versions")
    func sinceAllAndSinceVersionAreAndFilters() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        let httpClient = makeVersionedIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
        let cmd = try IssuesCommand.parse([
            "--since", "all",
            "--since-version", "6.17.0",
            "--format", "json",
        ])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let versions = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topVersions") == true }?.url)
        #expect(versions.issuesQueryItem(named: "filter.interval.startTime") == "2026-03-10T00:00:00Z")
        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true })
        #expect(TopVersionsFixture.displayNames(of: topIssues) == ["6.17.0 (20)"])
        let ids = try Envelope(output).data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids == ["FB-OLD", "FB-NEW"])
    }

    @Test("a version flag matching no version of the window lists nothing and names the versions seen")
    func noMatchingVersionHint() async throws {
        let httpClient = makeVersionedIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try IssuesCommand.parse(["--app-version", "9.9.9", "--format", "json"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.isEmpty == true)
        #expect(env.data["matchedVersions"]?.array?.isEmpty == true)
        let hint = try #require(env.data["hint"]?.string)
        #expect(hint.contains("--app-version 9.9.9"))
        #expect(hint.contains("6.17.0 (20), 6.16.0 (19), 6.15.0 (18)"))
        #expect(httpClient.requests.contains { $0.url?.path.hasSuffix("/reports/topIssues") == true } == false)
    }

    @Test("--app-version with a build number selects only that build")
    func appVersionWithBuild() async throws {
        let httpClient = makeVersionedIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try IssuesCommand.parse(["--app-version", "6.16.0 (19)", "--format", "json"])

        _ = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true })
        #expect(TopVersionsFixture.displayNames(of: topIssues) == ["6.16.0 (19)"])
    }

    @Test("by-day over a version filter asks for both the version names and the daily series")
    func byDayWithVersionFilter() async throws {
        let httpClient = makeVersionedIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try IssuesCommand.parse(["--by-day", "--app-version", "6.15.0", "--format", "json"])

        _ = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true })
        #expect(TopVersionsFixture.displayNames(of: topIssues) == ["6.15.0 (18)"])
        #expect(topIssues.url?.issuesQueryItem(named: "granularity") == "TIME_GRANULARITY_DAY")
    }

    @Test("by-day asks the report for daily granularity and samples no events for the trend")
    func byDayRequestsDailyGranularity() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z"))
        let httpClient = makeTrendHTTP()
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
        let cmd = try IssuesCommand.parse(["--by-day", "--format", "json"])

        _ = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url)
        #expect(topIssues.issuesQueryItem(named: "granularity") == "TIME_GRANULARITY_DAY")
        // Without --by-day the report is not asked for a series.
        let plain = makeTrendHTTP()
        _ = try await IssuesCommand.parse(["--format", "json"])
            .execute(ctx.withFirebaseHTTP(plain).container)
        let plainTopIssues = try #require(plain.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url)
        #expect(plainTopIssues.issuesQueryItem(named: "granularity") == nil)
        // Events are read only for lastSeenAt: one per issue, never a deep sample.
        let eventRequests = httpClient.requests.filter { $0.url?.path.hasSuffix("/events") == true }
        #expect(eventRequests.count == 1)
        #expect(eventRequests.first?.url?.issuesQueryItem(named: "page_size") == "1")
    }

    @Test("by-day JSON daily counts come from the report and sum to eventsCount")
    func byDayCountsSumToTotal() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z"))
        let ctx = Platform.testing(
            fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
        let cmd = try IssuesCommand.parse(["--by-day", "--format", "json"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(makeTrendHTTP()).container)

        let issue = try #require(try Envelope(output).data["issues"]?[0])
        let days = try #require(issue["dailyEvents"]?.array)
        // The whole-window total point, the zero day and the repeated day are not extra days.
        #expect(days.compactMap { $0["day"]?.string } == ["2026-06-01", "2026-06-07", "2026-06-08"])
        #expect(days.compactMap { $0["eventsCount"]?.int } == [700, 35, 2])
        #expect(issue["eventsCount"]?.int == 737)
        #expect(issue["dailyEventsSampledCount"]?.int == 737)
        #expect(issue["dailyEventsTruncated"]?.bool == false)
    }
}
