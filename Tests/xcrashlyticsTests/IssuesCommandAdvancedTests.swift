import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    @Test("renders NDJSON with one issue per line")
    func rendersNDJSON() async throws {
        let fs = try makeMultiIssuesHTTPConfig()
        let http = makeMultiIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--format", "ndjson", "--limit", "200"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let lines = try JSON.lines(output)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0["schemaVersion"]?.int == 1 })
        #expect(lines.allSatisfy { $0["id"]?.string?.hasPrefix("FB-I") == true })
        #expect(lines.allSatisfy { $0["issues"] == nil && $0["data"] == nil })
    }

    @Test("uses the active profile app id for Firebase requests")
    func usesActiveProfileAppId() async throws {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(
            appId: "1:1111111111:ios:debug",
            activeProfile: "staging",
            profiles: [
                "staging": AppProfile(appId: "1:2222222222:ios:staging")
            ]
        ))
        var requestedPath: String?
        let http = MockHTTPTransport { request in
            requestedPath = request.url?.path
            return try makeIssuesHTTP().handler!(request)
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["--format", "json"])

        _ = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        #expect(requestedPath?.contains("/projects/2222222222/apps/1:2222222222:ios:staging/") == true)
    }

    @Test("query searches latest event metadata when issue fields do not match")
    func querySearchesEventMetadata() async throws {
        let fs = try makeConfig()
        let http = makeMetricKitHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([
            "com.metrickit.diagnostics.cpu",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.contains { $0["id"]?.string == "FB-MX" } == true)
        #expect(env.data["eventMetadataSamples"]?.int == 1)
    }

    @Test("filters issues by event domain and userInfo key")
    func filtersByEventDomainAndUserInfo() async throws {
        let fs = try makeConfig()
        let http = makeMetricKitHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([
            "--domain", "com.metrickit.diagnostics.cpu",
            "--user-info-key", "reason=cpu spike",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-MX"))
        #expect(!ids.contains("FB-OTHER"))
    }

    @Test("filters issues by raw Firebase user id across sampled events")
    func filtersIssuesByUserId() async throws {
        let fs = try makeConfig()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([
            "--user-id", "target-user",
            "--events-per-issue", "2",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(makeUserIssuesHTTP())

        )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I1"))
        #expect(!ids.contains("FB-I2"))
        // The raw user id is a filter input only; it must not leak anywhere in the output.
        #expect(!output.contains("target-user"))
    }

    @Test("filters Xcode crashes using the same issue criteria")
    func filtersXcodeCrashesWithIssueCriteria() async throws {
        let http = makeRankedIssuesHTTP(matchIndex: nil, total: 2)
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        let crashDir = "/crashes"
        fs.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["missing", "--xcode", "--format", "json"])
        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http),
            crashDirectories: [crashDir]
        )
        let env = try Envelope(output)
        // sample.crash does not match "missing", so the Xcode list is present but filtered empty.
        #expect(env.data["xcodeCrashes"]?.array?.isEmpty == true)
        #expect(env.data["symbolicationHint"] == nil)
    }

    @Test("since all disables time filtering while since-version still applies")
    func sinceAllAndSinceVersionAreAndFilters() async throws {
        let fs = try makeConfig()
        let http = makeVersionedIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([
            "--since", "all",
            "--since-version", "6.17.0",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-NEW"))
        #expect(!ids.contains("FB-OLD"))
    }

    @Test("by-day adds per-issue event trend counts")
    func byDayAddsTrendCounts() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z"))
        let fs = try makeConfig()
        let http = makeTrendHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try IssuesCommand.parse([
            "--since", "7d",
            "--by-day",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        let issue = try #require(env.data["issues"]?[0])
        let days = try #require(issue["dailyEvents"]?.array)
        try #require(days.count == 2)
        #expect(days[0]["day"]?.string == "2026-06-07")
        #expect(days[0]["eventsCount"]?.int == 2)
        #expect(days[1]["day"]?.string == "2026-06-08")
        #expect(days[1]["eventsCount"]?.int == 1)
        #expect(issue["dailyEventsTruncated"]?.bool == false)
    }

    @Test("bare listing samples each issue's latest event for lastSeenAt")
    func bareListingAddsLastSeen() async throws {
        let fs = try makeMultiIssuesHTTPConfig()
        let http = makeMultiIssuesWithEventsHTTP()
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
        let issues = env.data["issues"]?.array ?? []
        func lastSeen(_ id: String) -> String? {
            issues.first { $0["id"]?.string == id }?["lastSeenAt"]?.string
        }
        #expect(lastSeen("FB-I1") == "2026-06-07T20:00:00Z")
        #expect(lastSeen("FB-I2") == "2026-06-01T20:00:00Z")
    }

    @Test("by-day flags truncated trends when sample covers fewer events than total")
    func byDayFlagsTruncatedTrend() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z"))
        let fs = try makeConfig()
        let http = makeTruncatedTrendHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try IssuesCommand.parse([
            "--by-day",
            "--format", "json",
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        let issue = try #require(env.data["issues"]?[0])
        #expect(issue["dailyEventsSampledCount"]?.int == 3)
        #expect(issue["dailyEventsTruncated"]?.bool == true)
    }

    @Test("by-day text marks oldest sampled day partial for truncated trends")
    func byDayTextMarksTruncatedTrend() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z"))
        let fs = try makeConfig()
        let http = makeTruncatedTrendHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock(now)
        )
        let cmd = try IssuesCommand.parse(["--by-day"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        #expect(output.contains("2026-06-07:≥2"))
        #expect(output.contains("2026-06-08:1"))
        #expect(output.contains("(sampled newest 3 of 737 events)"))
    }
}
