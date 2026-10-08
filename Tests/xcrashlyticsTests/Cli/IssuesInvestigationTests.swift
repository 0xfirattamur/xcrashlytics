import Foundation
import Testing
@testable import xcrashlytics

/// `issues`: report window, filters that need events, local Xcode crashes, validation, and warnings.
@Suite("xcrashlytics issues investigation")
struct IssuesInvestigationTests {
    private let appId = "1:1234567890:ios:abcdef"
    private let now = ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z")!

    // MARK: - Fixtures

    private func config() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    private func context(_ fileStore: InMemoryFileStore, _ httpClient: FakeHTTPClient) -> Platform {
        Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(now))
            .withFirebaseHTTP(httpClient)
    }

    private func crashFixture() throws -> String {
        let url = Bundle.module.url(forResource: "sample.crash", withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func seedCrashes(_ fileStore: InMemoryFileStore, count: Int, in directory: String = "/crashes") throws {
        let text = try crashFixture()
        for index in 0..<count {
            let id = String(format: "AAAAAAAA-BBBB-CCCC-DDDD-%012d", index)
            let body = text.replacingOccurrences(of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", with: id)
            fileStore.seed("\(directory)/\(index).crash", text: body, modificationDate: Date(timeIntervalSince1970: Double(1_000 - index)))
        }
    }

    private struct Fake {
        var id: String
        var title: String
        var errorType = "EXC_BAD_ACCESS"
        var events = 10
        var eventTimes: [String] = ["2026-06-07T10:00:00Z"]
        var userIds: [String?] = []
    }

    private func server(_ issues: [Fake], eventsStatus: Int = 200) -> FakeHTTPClient {
        FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/reports/topIssues") {
                let groups = issues.map { issue in
                    #"""
                    {"issue":{"id":"\#(issue.id)","title":"\#(issue.title)","errorType":"\#(issue.errorType)",
                    "lastSeenVersion":"6.16.0"},"metrics":[{"eventsCount":"\#(issue.events)","impactedUsersCount":"3"}]}
                    """#
                }
                return FakeHTTPClient.response(url, status: 200, body: Data("{\"groups\":[\(groups.joined(separator: ","))]}".utf8))
            }
            guard eventsStatus == 200 else {
                return FakeHTTPClient.response(url, status: eventsStatus, body: Data(#"{"error":{"message":"gone"}}"#.utf8))
            }
            let id = url.issuesQueryItem(named: "filter.issue.id") ?? ""
            let issue = issues.first { $0.id == id }
            let events = (issue?.eventTimes ?? []).enumerated().map { index, time in
                let user = issue.flatMap { index < $0.userIds.count ? $0.userIds[index] : nil }
                let userJSON = user.map { #","user":{"id":"\#($0)"}"# } ?? ""
                return #"{"eventId":"E\#(index)","eventTime":"\#(time)"\#(userJSON)}"#
            }
            return FakeHTTPClient.response(url, status: 200, body: Data("{\"events\":[\(events.joined(separator: ","))]}".utf8))
        }
    }

    private func topIssueRequests(_ httpClient: FakeHTTPClient) -> [URL] {
        httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/reports/topIssues") }
    }

    private func failureCode(_ args: [String], httpClient: FakeHTTPClient? = nil) async throws -> String? {
        let transport = httpClient ?? FakeHTTPClient { _ in throw HTTPTransportError.transport("no request expected") }
        do {
            _ = try await IssuesCommand.parse(["--format", "json"] + args).execute(context(try config(), transport).container)
            return nil
        } catch {
            #expect(transport.requests.isEmpty, "\(args) must fail before any request")
            return CommandRunner.failure(for: error).code
        }
    }

    // MARK: - Report window

    @Test("without --since the counts cover the last 7 days, and the window is reported")
    func defaultWindow() async throws {
        let httpClient = server([Fake(id: "I1", title: "Crash")])
        let output = try await IssuesCommand.parse(["--format", "json"]).execute(context(try config(), httpClient).container)

        let url = try #require(topIssueRequests(httpClient).first)
        #expect(url.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-01T00:00:00Z")
        #expect(url.issuesQueryItem(named: "filter.interval.endTime") == "2026-06-08T00:00:00Z")
        let data = try Envelope(output).data
        #expect(data["window"]?["since"]?.string == "2026-06-01T00:00:00Z")
        #expect(data["since"] == nil)
    }

    @Test("--since all is the 90-day maximum; longer windows and malformed values are BAD_INPUT before any request")
    func sinceBounds() async throws {
        let httpClient = server([Fake(id: "I1", title: "Crash")])
        _ = try await IssuesCommand.parse(["--since", "all", "--format", "json"]).execute(context(try config(), httpClient).container)
        #expect(topIssueRequests(httpClient).first?.issuesQueryItem(named: "filter.interval.startTime") == "2026-03-10T00:00:00Z")

        for since in ["91d", "0d", "-3d", "7"] {
            #expect(try await failureCode(["--since=\(since)"]) == "BAD_INPUT", "--since \(since)")
        }
    }

    // MARK: - Filters that need events

    @Test("a dotted query matched by the issue title keeps eventless issues and samples no events for the filter")
    func dottedQueryOnEventlessIssue() async throws {
        let httpClient = server([Fake(id: "I1", title: "[Core] F1.swift - F1.run()", eventTimes: [])])
        let output = try await IssuesCommand.parse(["F1.swift", "--format", "json"]).execute(context(try config(), httpClient).container)

        let data = try Envelope(output).data
        #expect(data["issues"]?.array?.compactMap { $0["id"]?.string } == ["FB-I1"])
        #expect(data["eventMetadataSamples"] == nil)
        #expect(data["hint"] == nil)
    }

    @Test("a dotted query the title misses is confirmed by sampled events; eventless issues are dropped")
    func dottedQueryDeferredToEvents() async throws {
        let httpClient = FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"groups":[{"issue":{"id":"I1","title":"A","errorType":"FATAL"}},{"issue":{"id":"I2","title":"B","errorType":"FATAL"}}]}
                """#.utf8))
            }
            let id = url.issuesQueryItem(named: "filter.issue.id")
            let body = id == "I1"
                ? #"{"events":[{"eventId":"E1","error":{"domain":"com.example.Boom"}}]}"#
                : #"{"events":[]}"#
            return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
        }
        let output = try await IssuesCommand.parse(["com.example.Boom", "--format", "json"])
            .execute(context(try config(), httpClient).container)
        #expect(try Envelope(output).data["issues"]?.array?.compactMap { $0["id"]?.string } == ["FB-I1"])
    }

    @Test("--user-id scans --events-per-issue newest events and warns when none of them matched")
    func userIdScanDepthWarning() async throws {
        let httpClient = server([Fake(id: "I1", title: "Crash", eventTimes: ["2026-06-07T10:00:00Z", "2026-06-07T09:00:00Z"], userIds: ["a", "b"])])
        let output = try await IssuesCommand.parse(["--user-id", "nobody", "--events-per-issue", "2", "--format", "json"])
            .execute(context(try config(), httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.isEmpty == true)
        #expect(env.warningCodes == ["SCAN_TRUNCATED"])
        #expect(httpClient.requests.contains { $0.url?.issuesQueryItem(named: "page_size") == "2" })
    }

    @Test("--user-id without --events-per-issue scans 50 events, not the --by-day depth")
    func userIdDefaultDepth() async throws {
        let httpClient = server([Fake(id: "I1", title: "Crash", userIds: [])])
        _ = try await IssuesCommand.parse(["--user-id", "x", "--format", "json"]).execute(context(try config(), httpClient).container)
        #expect(httpClient.requests.contains { $0.url?.path.hasSuffix("/events") == true && $0.url?.issuesQueryItem(named: "page_size") == "50" })
    }

    // MARK: - type / errorType

    @Test("--type FATAL matches Firebase's errorType and JSON reports errorType")
    func typeAndErrorTypeField() async throws {
        let httpClient = server([Fake(id: "I1", title: "A", errorType: "FATAL"), Fake(id: "I2", title: "B", errorType: "NON_FATAL")])
        let output = try await IssuesCommand.parse(["--type", "fatal", "--format", "json"]).execute(context(try config(), httpClient).container)

        let issues = try #require(try Envelope(output).data["issues"]?.array)
        #expect(issues.compactMap { $0["id"]?.string } == ["FB-I1"])
        #expect(issues.first?["errorType"]?.string == "FATAL")
        #expect(issues.first?["source"]?.string == "firebase")
    }

    // MARK: - Local Xcode crashes

    @Test("--crash-directory alone implies --xcode")
    func crashDirectoryImpliesXcode() async throws {
        let fileStore = try config()
        try seedCrashes(fileStore, count: 1)
        let output = try await IssuesCommand.parse(["--crash-directory", "/crashes", "--format", "json"])
            .execute(context(fileStore, server([])).container)
        let xcode = try #require(try Envelope(output).data["xcodeCrashes"]?.array)
        #expect(xcode.count == 1)
        #expect(xcode.first?["source"]?.string == "xcode")
    }

    @Test("--limit caps Xcode crashes too, and the matched count says how many were cut")
    func limitCapsXcode() async throws {
        let fileStore = try config()
        try seedCrashes(fileStore, count: 3)
        let output = try await IssuesCommand.parse(["--xcode", "--crash-directory", "/crashes", "--limit", "2", "--format", "json"])
            .execute(context(fileStore, server([])).container)
        let data = try Envelope(output).data
        #expect(data["xcodeCrashes"]?.array?.count == 2)
        #expect(data["matchedXcodeCrashesCount"]?.int == 3)
    }

    @Test("Xcode crashes honor --type and --min-events; event-only filters exclude them with a warning")
    func xcodeSharedFiltersAndWarning() async throws {
        let fileStore = try config()
        try seedCrashes(fileStore, count: 1)
        func run(_ extra: [String]) async throws -> Envelope {
            try Envelope(try await IssuesCommand.parse(["--crash-directory", "/crashes", "--format", "json"] + extra)
                .execute(context(fileStore, server([])).container))
        }
        #expect(try await run(["--type", "EXC_BAD_ACCESS"]).data["xcodeCrashes"]?.array?.count == 1)
        #expect(try await run(["--type", "FATAL"]).data["xcodeCrashes"]?.array?.isEmpty == true)
        #expect(try await run(["--min-events", "5"]).data["xcodeCrashes"]?.array?.isEmpty == true)
        let excluded = try await run(["--user-id", "u"])
        #expect(excluded.data["xcodeCrashes"]?.array?.isEmpty == true)
        #expect(excluded.warningCodes.contains("XCODE_EXCLUDED_BY_FILTER"))
    }

    @Test("without a Firebase app id, --xcode lists local crashes and warns FIREBASE_SKIPPED")
    func firebaseSkipped() async throws {
        let fileStore = InMemoryFileStore()
        try seedCrashes(fileStore, count: 1)
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.transport("Firebase must not be called") }
        let output = try await IssuesCommand.parse(["--xcode", "--crash-directory", "/crashes", "--format", "json"])
            .execute(context(fileStore, httpClient).container)

        let env = try Envelope(output)
        #expect(env.warningCodes == ["FIREBASE_SKIPPED"])
        #expect(env.data["xcodeCrashes"]?.array?.count == 1)
        #expect(env.data["issues"]?.array?.isEmpty == true)
        #expect(httpClient.requests.isEmpty)
    }

    @Test("without --xcode a missing app id is still CONFIG_MISSING")
    func missingAppIdWithoutXcode() async throws {
        do {
            _ = try await IssuesCommand.parse(["--format", "json"]).execute(context(InMemoryFileStore(), server([])).container)
            Issue.record("expected CONFIG_MISSING")
        } catch {
            #expect(CommandRunner.failure(for: error).code == "CONFIG_MISSING")
        }
    }

    // MARK: - ndjson

    @Test("ndjson carries Firebase issues, Xcode crashes, and a final hint record, each with kind")
    func ndjsonRecords() async throws {
        let fileStore = try config()
        try seedCrashes(fileStore, count: 1)
        let httpClient = server([Fake(id: "I1", title: "A", errorType: "FATAL")])
        let output = try await IssuesCommand.parse(["--type", "EXC_BAD_ACCESS", "--crash-directory", "/crashes", "--format", "ndjson"])
            .execute(context(fileStore, httpClient).container)

        let lines = try JSON.lines(output)
        #expect(lines.map { $0["kind"]?.string } == ["xcodeCrash", "hint"])
        #expect(lines[0]["source"]?.string == "xcode")
        #expect(lines[1]["hint"]?.string == "0 matches in all 1 fetched issues.")
        #expect(lines.allSatisfy { $0["schemaVersion"]?.int == 1 })
    }

    @Test("ndjson issue records say kind issue; no hint record when there is nothing to hint")
    func ndjsonIssueKind() async throws {
        let output = try await IssuesCommand.parse(["--format", "ndjson"])
            .execute(context(try config(), server([Fake(id: "I1", title: "A")])).container)
        let lines = try JSON.lines(output)
        #expect(lines.map { $0["kind"]?.string } == ["issue"])
        #expect(lines.first?["id"]?.string == "FB-I1")
    }

    // MARK: - Flags

    @Test("--user-info-key takes one value per flag, so a trailing query survives")
    func userInfoKeyIsSingleValue() throws {
        let cmd = try IssuesCommand.parse(["--user-info-key", "a=b", "--user-info-key", "c", "blur"])
        #expect(cmd.query == "blur")
        #expect(cmd.userInfoKey == ["a=b", "c"])
    }

    @Test("numeric, empty, and version flags are validated as BAD_INPUT before any request")
    func validation() async throws {
        let bad: [[String]] = [
            ["--limit", "0"], ["--search-limit", "0"], ["--events-per-issue", "0"], ["--min-events=-1"],
            ["--since-version", "abc"], ["--app-version", "1..2"], ["--since-version", ""], ["--app-version", ""],
            ["--file", ""], ["--symbol", " "], ["--type", ""], ["--user-id", ""], ["--match", ""], ["--domain", ""],
        ]
        for args in bad {
            #expect(try await failureCode(args) == "BAD_INPUT", "\(args)")
        }
    }

    // MARK: - Warnings

    @Test("--search-limit above 2000 is capped with a warning")
    func searchLimitCapped() async throws {
        let output = try await IssuesCommand.parse(["--search-limit", "5000", "--format", "json"])
            .execute(context(try config(), server([Fake(id: "I1", title: "A")])).container)
        let env = try Envelope(output)
        #expect(env.data["searchLimit"]?.int == 2_000)
        #expect(env.warningCodes == ["SEARCH_LIMIT_CAPPED"])
    }

    @Test("a filtered search that exhausted its window without filling --limit warns SEARCH_TRUNCATED")
    func searchTruncated() async throws {
        let httpClient = server((1...3).map { Fake(id: "I\($0)", title: "A\($0)") })
        let truncated = try Envelope(try await IssuesCommand.parse(["zzz", "--search-limit", "3", "--format", "json"])
            .execute(context(try config(), httpClient).container))
        #expect(truncated.warningCodes == ["SEARCH_TRUNCATED"])

        let complete = try Envelope(try await IssuesCommand.parse(["zzz", "--search-limit", "10", "--format", "json"])
            .execute(context(try config(), httpClient).container))
        #expect(complete.warningCodes.isEmpty)
    }

    @Test("a failing last-seen lookup warns and omits lastSeenAt instead of failing the listing")
    func lastSeenIsBestEffort() async throws {
        let httpClient = server([Fake(id: "I1", title: "A"), Fake(id: "I2", title: "B")], eventsStatus: 404)
        let output = try await IssuesCommand.parse(["--format", "json"]).execute(context(try config(), httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["issues"]?.array?.count == 2)
        #expect(env.data["issues"]?[0]?["lastSeenAt"] == nil)
        #expect(env.warningCodes == ["LAST_SEEN_UNAVAILABLE"])
    }

    @Test("lastSeenAt is the time of the newest event, which the API lists first; one event is requested")
    func lastSeenIsNewest() async throws {
        let httpClient = server([Fake(id: "I1", title: "A", eventTimes: ["2026-06-05T00:00:00Z", "2026-06-01T00:00:00Z"])])
        let output = try await IssuesCommand.parse(["--by-day", "--format", "json"]).execute(context(try config(), httpClient).container)
        #expect(try Envelope(output).data["issues"]?[0]?["lastSeenAt"]?.string == "2026-06-05T00:00:00Z")
        let eventRequests = httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/events") }
        #expect(eventRequests.compactMap { $0.issuesQueryItem(named: "page_size") } == ["1"])
    }

    @Test("lastSeenAt and --user-id sampling read events inside the report window, not the API's 7-day default")
    func samplingUsesReportWindow() async throws {
        let httpClient = server([Fake(id: "I1", title: "A", eventTimes: ["2026-05-20T00:00:00Z"], userIds: ["u"])])
        _ = try await IssuesCommand.parse(["--since", "30d", "--user-id", "u", "--format", "json"])
            .execute(context(try config(), httpClient).container)
        let eventRequests = httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/events") }
        // One request to match the user, one for lastSeenAt.
        #expect(eventRequests.count == 2)
        for url in eventRequests {
            #expect(url.issuesQueryItem(named: "filter.interval.startTime") == "2026-05-09T00:00:00Z")
            #expect(url.issuesQueryItem(named: "filter.interval.endTime") == "2026-06-08T00:00:00Z")
        }
    }

    @Test("a bare listing reads last-seen events from the default 7-day report window")
    func lastSeenUsesDefaultWindow() async throws {
        let httpClient = server([Fake(id: "I1", title: "A")])
        _ = try await IssuesCommand.parse(["--format", "json"]).execute(context(try config(), httpClient).container)
        let event = try #require(httpClient.requests.compactMap(\.url).first { $0.path.hasSuffix("/events") })
        #expect(event.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-01T00:00:00Z")
    }
}
