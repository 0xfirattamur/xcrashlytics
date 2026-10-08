import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics groups")
struct GroupsCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("groups related live Firebase issues")
    func groupsFirebaseIssues() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try GroupsCommand.parse([])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        #expect(output.contains("blurdetectionservice.classifywithml(_:)"))
        #expect(output.contains("firebase: 2 issues"))
        #expect(output.contains("FB-I1, FB-I2"))
        #expect(output.contains("50 events / 15 users"))
    }

    @Test("renders grouped Firebase issues as JSON")
    func rendersJSON() async throws {
        let fileStore = try makeConfig()
        let httpClient = makeIssuesHTTP()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try GroupsCommand.parse(["--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient).container)

        let env = try Envelope(output)
        let groups = try #require(env.data["groups"]?.array)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group["symbol"]?.string == "blurdetectionservice.classifywithml(_:)")
        #expect(group["totalEvents"]?.int == 50)
        #expect(group["crossSource"]?.bool == false)
        #expect(group["firebase"]?.array?.compactMap { $0["id"]?.string } == ["FB-I1", "FB-I2"])
    }

    // MARK: - Report window

    @Test("sends an explicit 7-day interval by default and --since overrides it; JSON reports the window")
    func sendsWindow() async throws {
        let httpClient = makeIssuesHTTP()
        let dateProvider = FixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: dateProvider)
            .withFirebaseHTTP(httpClient)

        let output = try await GroupsCommand.parse(["--format", "json"]).execute(ctx.container)
        let query = try #require(httpClient.requests.first?.url?.query)
        #expect(query.contains("filter.interval.startTime=2027-01-08T"))
        let window = try #require(try Envelope(output).data["window"])
        #expect(window["since"]?.string?.hasPrefix("2027-01-08T") == true)
        #expect(window["until"]?.string?.hasPrefix("2027-01-15T") == true)

        let http30 = makeIssuesHTTP()
        _ = try await GroupsCommand.parse(["--since", "30d"]).execute(ctx.withFirebaseHTTP(http30).container)
        #expect(try #require(http30.requests.first?.url?.query).contains("filter.interval.startTime=2026-12-16T"))
    }

    @Test("a window beyond 90 days is BAD_INPUT before any request")
    func rejectsHugeWindow() async throws {
        let httpClient = makeIssuesHTTP()
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
            .withFirebaseHTTP(httpClient)
        await #expect(throws: InvalidInputError.self) {
            _ = try await GroupsCommand.parse(["--since", "120d"]).execute(ctx.container)
        }
        #expect(httpClient.requests.isEmpty)
    }

    // MARK: - Argument validation (failures go through CommandRunner)

    @Test("bad --limit / --firebase-limit / ndjson are ValidationErrors from run, never a trap")
    func validatesArguments() async throws {
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
            .withFirebaseHTTP(makeIssuesHTTP())
        for args in [["--limit=-1"], ["--limit=0"], ["--firebase-limit=0"], ["--firebase-limit=-5"], ["--format", "ndjson"]] {
            let cmd = try GroupsCommand.parse(args)
            await #expect(throws: ValidationError.self, "\(args)") {
                _ = try await cmd.execute(ctx.container)
            }
        }
    }

    // MARK: - Local crashes

    private let crashDirectory = "/crashes"

    private func localContext(appId: Bool, httpClient: FakeHTTPClient) throws -> Platform {
        let fileStore = appId ? try makeConfig() : InMemoryFileStore()
        fileStore.seed(
            "\(crashDirectory)/exampleapp.crash",
            text: try XcodeFixtures.text("sample-symbolicated.crash"),
            modificationDate: Date(timeIntervalSince1970: 1_000))
        fileStore.seed(
            "\(crashDirectory)/other.crash",
            text: try XcodeFixtures.text("system-frame-first.crash")
                .replacingOccurrences(of: "ExampleViewController crashNow", with: "OtherController explode"),
            modificationDate: Date(timeIntervalSince1970: 2_000))
        let base = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        return appId ? base.withFirebaseHTTP(httpClient) : Platform.testing(
            fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider(), httpClient: httpClient)
    }

    private func crashIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            let body = #"""
            { "groups": [
              { "issue": { "id": "I9", "title": "[ExampleApp] ExampleViewController.swift - -[ExampleViewController crashNow]", "errorType": "FATAL" },
                "metrics": [{ "eventsCount": "7", "impactedUsersCount": "2" }] },
              { "issue": { "id": "I8", "title": "[ExampleApp] Unrelated.swift - Unrelated.thing()", "errorType": "FATAL" },
                "metrics": [{ "eventsCount": "99", "impactedUsersCount": "9" }] }
            ] }
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    @Test("--xcode links a local crash to the Firebase issue with the same culprit")
    func crossSourceGroup() async throws {
        let ctx = try localContext(appId: true, httpClient: crashIssuesHTTP())
        let output = try await GroupsCommand.parse(["--xcode", "--crash-directory", crashDirectory, "--format", "json"])
            .execute(ctx.container)
        let env = try Envelope(output)
        let groups = try #require(env.data["groups"]?.array)
        let cross = try #require(groups.first)
        #expect(cross["crossSource"]?.bool == true)
        #expect(cross["firebase"]?.array?.first?["id"]?.string == "FB-I9")
        #expect(cross["xcode"]?.array?.first?["event"]?["id"]?.string == "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(env.warningCodes.isEmpty)
    }

    @Test("--xcode without a configured Firebase app returns local crashes with FIREBASE_SKIPPED")
    func localOnlyWithoutFirebase() async throws {
        let httpClient = FakeHTTPClient()
        let ctx = try localContext(appId: false, httpClient: httpClient)
        let output = try await GroupsCommand.parse(["--xcode", "--crash-directory", crashDirectory, "--format", "json"])
            .execute(ctx.container)
        let env = try Envelope(output)
        #expect(env.warningCodes == ["FIREBASE_SKIPPED"])
        #expect(try #require(env.data["groups"]?.array).count == 2)
        #expect(httpClient.requests.isEmpty)
    }

    @Test("without --xcode a missing Firebase app is still an error")
    func missingAppIdWithoutXcode() async throws {
        let ctx = try localContext(appId: false, httpClient: FakeHTTPClient())
        await #expect(throws: ConfigError.missingAppId) {
            _ = try await GroupsCommand.parse([]).execute(ctx.container)
        }
    }

    @Test("groups <issue> --xcode keeps only the issue's group, not every local-only group")
    func issueFilterAppliesToLocals() async throws {
        let ctx = try localContext(appId: true, httpClient: crashIssuesHTTP())
        let output = try await GroupsCommand.parse(
            ["FB-I9", "--xcode", "--crash-directory", crashDirectory, "--format", "json"]).execute(ctx.container)
        let env = try Envelope(output)
        let groups = try #require(env.data["groups"]?.array)
        #expect(groups.count == 1)
        #expect(groups[0]["firebase"]?.array?.first?["id"]?.string == "FB-I9")
        #expect(groups[0]["xcode"]?.array?.count == 1)
        #expect(env.warningCodes.isEmpty)
    }

    @Test("groups <issue> outside the fetched window warns instead of silently printing nothing")
    func issueNotInWindow() async throws {
        let ctx = try localContext(appId: true, httpClient: crashIssuesHTTP())
        let output = try await GroupsCommand.parse(["FB-NOPE", "--format", "json"]).execute(ctx.container)
        let env = try Envelope(output)
        #expect(try #require(env.data["groups"]?.array).isEmpty)
        #expect(env.warningCodes == ["ISSUE_NOT_IN_WINDOW"])
    }

    private func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    private func makeIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let body = #"""
            {
              "groups": [
                {
                  "issue": {
                    "id": "I1",
                    "title": "[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "42", "impactedUsersCount": "12" }]
                },
                {
                  "issue": {
                    "id": "I2",
                    "title": "[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "8", "impactedUsersCount": "3" }]
                }
              ]
            }
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }
}
