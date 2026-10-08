import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics show")
struct ShowCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("renders detail block for an XC- id")
    func rendersDetail() async throws {
        let fileStore = InMemoryFileStore()
        let configJSON = #"{"activeProfile":"dev","profiles":{"dev":"#
            + #"{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        fileStore.seed("\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json", text: configJSON)
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))

        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: SystemDateProvider()
        )

        let cmd = try ShowCommand.parse([
            "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        ])
        let out = try await cmd.execute(ctx.container)

        #expect(out.contains("Exception: EXC_BAD_ACCESS"))
        #expect(out.contains("-[ExampleViewController crashNow]"))
    }

    @Test("rejects unknown id prefix")
    func rejectsBadId() async throws {
        let ctx = Platform.testing(
            fileStore: InMemoryFileStore(),
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: SystemDateProvider()
        )
        let cmd = try ShowCommand.parse(["BOGUS-abc"])
        await #expect(throws: (any Error).self) {
            _ = try await cmd.execute(ctx.container)
        }
    }

    @Test("FB issue detail includes latest event frames")
    func firebaseShowIncludesLatestEventFrames() async throws {
        let fileStore = try makeConfig()
        let httpClient = FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"groups":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{
              "eventId":"E1",
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]
            }]}
            """#.utf8))
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try ShowCommand.parse(["FB-I1", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient)
        .container)

        let data = try Envelope(output).data
        #expect(data["id"]?.string == "FB-I1")
        #expect(data["providerId"]?.string == "I1")
        #expect(data["frames"]?[0]?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
        #expect(data["frames"]?[0]?["file"]?.string == "BlurDetectionService.swift")
    }

    @Test("FB issue show renders a sampled summary header")
    func firebaseShowRendersSummaryHeader() async throws {
        let fileStore = try makeConfig()
        let httpClient = FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","firstSeenVersion":"6.2.0","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"groups":[
                  {"version":{"displayVersion":"6.2.0","buildVersion":"1","displayName":"6.2.0 (1)"},"metrics":[{"eventsCount":"0"}]},
                  {"version":{"displayVersion":"6.10.0","buildVersion":"7","displayName":"6.10.0 (7)"},"metrics":[{"eventsCount":"3"}]},
                  {"version":{"displayVersion":"6.9.1","buildVersion":"5","displayName":"6.9.1 (5)"},"metrics":[{"eventsCount":"2"}]}
                ]}
                """#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E1","eventTime":"2026-06-10T08:00:00Z",
               "device":{"model":"iPhone 17 Pro Max"},
               "platform":"IOS","operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"u1"},
               "threads":[{"crashed":true,"frames":[{"symbol":"doWork()","library":"Core"}]}]},
              {"eventId":"E2","eventTime":"2026-06-01T08:00:00Z",
               "device":{"model":"iPhone 16"},
               "platform":"IOS","operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"u2"}}
            ]}
            """#.utf8))
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try ShowCommand.parse(["FB-I1"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient)
        .container)

        #expect(output.contains("Sampled:   newest 2 events, 2026-06-01 → 2026-06-10, 2 users"))
        #expect(output.contains("OS:        iOS 26.4.1 ×2"))
        #expect(output.contains("Devices:   iPhone 16 ×1, iPhone 17 Pro Max ×1"))
        #expect(output.contains("doWork()"))
        // Range is semver over versions with events: 6.2.0 has none, 6.10.0 sorts above 6.9.1.
        #expect(output.contains("Range:     6.9.1 (5) … 6.10.0 (7)"))
    }

    @Test("FB issue show can filter latest event frames to app frames")
    func firebaseShowFiltersAppFrames() async throws {
        let fileStore = try makeConfig()
        let httpClient = FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"groups":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{
              "eventId":"E1",
              "threads":[{"crashed":true,"frames":[
                {"symbol":"<redacted>","library":"libsystem_kernel.dylib","owner":"SYSTEM"},
                {
                  "symbol":"BlurDetectionService.classifyWithML(_:)",
                  "library":"Core",
                  "file":"BlurDetectionService.swift",
                  "line":"42",
                  "owner":"APPLICATION",
                  "blamed":true
                }
              ]}]
            }]}
            """#.utf8))
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try ShowCommand.parse(["FB-I1", "--app-frames-only", "--format", "json"])

        let output = try await cmd.execute(
            ctx.withFirebaseHTTP(httpClient)
        .container)

        let frames = try #require(Envelope(output).data["frames"]?.array)
        #expect(frames.count == 1)
        #expect(frames.first?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
        #expect(!frames.contains { $0["binaryName"]?.string == "libsystem_kernel.dylib" })
    }

    @Test("FB event id shows that event with its build and the issue's exception")
    func firebaseEventShowIncludesFrames() async throws {
        let fileStore = try makeConfig()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try ShowCommand.parse(["FB-I1/events/E1", "--format", "json"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(singleEventHTTP()).container)

        let data = try Envelope(output).data
        #expect(data["id"]?.string == "FB-I1/events/E1")
        #expect(data["deviceModel"]?.string == "iPhone 17 Pro Max")
        #expect(data["bundleVersion"]?.string == "6.16.0")
        #expect(data["appBuild"]?.string == "937")
        #expect(data["memoryFreeBytes"]?.int == 1_048_576)
        #expect(data["exception"]?["exceptionType"]?.string == "EXC_BAD_ACCESS")
        #expect(data["frames"]?[0]?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
    }

    @Test("a pasted console sessionEventKey resolves to the API event id")
    func firebaseEventShowAcceptsSessionEventKey() async throws {
        let fileStore = try makeConfig()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try ShowCommand.parse(["FB-I1/events/ca5e0601db004a358cbbed734042db17_E1", "--format", "json"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(singleEventHTTP()).container)

        #expect(try Envelope(output).data["id"]?.string == "FB-I1/events/E1")
    }

    @Test("--format ndjson is BAD_INPUT with the JSON error contract, not a parse error")
    func rejectsNdjson() async throws {
        let ctx = Platform.testing(fileStore: InMemoryFileStore(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try ShowCommand.parse(["FB-I1", "--format", "ndjson"])
        do {
            _ = try await cmd.execute(ctx.container)
            Issue.record("expected BAD_INPUT")
        } catch {
            let failure = CommandRunner.failure(for: error)
            #expect(failure.code == "BAD_INPUT")
            #expect(failure.exitCode == 5)
            #expect(failure.message.contains("ndjson"))
        }
    }

    @Test("frame filter flags on an XC id warn FRAME_FILTER_IGNORED and still show every frame")
    func frameFlagsWithXcodeId() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/crashes/A.crash", text: try loadFixture("sample.crash"))
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try ShowCommand.parse([
            "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "--app-frames-only", "--crash-directory", "/crashes", "--format", "json",
        ])

        let env = try Envelope(try await cmd.execute(ctx.container))

        #expect(env.warningCodes == ["FRAME_FILTER_IGNORED"])
        #expect(env.data["frames"]?.array?.isEmpty == false)
    }

    @Test("--crashing-thread-only warns NO_CRASHED_THREAD when the newest event has none, and reports the crashed thread index")
    func crashingThreadOnlyWarnings() async throws {
        func httpClient(crashed: Bool) -> FakeHTTPClient {
            FakeHTTPClient { request in
                if request.url?.path.hasSuffix("/issues/I1") == true {
                    return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"id":"I1","title":"t","errorType":"FATAL"}"#.utf8))
                }
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"events":[{"eventId":"E1","threads":[
                  {"crashed":false,"frames":[{"symbol":"idle()"}]},
                  {"crashed":\#(crashed),"frames":[{"symbol":"boom()"}]}]}]}
                """#.utf8))
            }
        }
        let ctx = Platform.testing(fileStore: try makeConfig(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())

        let none = try Envelope(try await ShowCommand.parse(["FB-I1", "--crashing-thread-only", "--format", "json"])
            .execute(ctx.withFirebaseHTTP(httpClient(crashed: false)).container))
        #expect(none.warningCodes == ["NO_CRASHED_THREAD"])

        let found = try Envelope(try await ShowCommand.parse(["FB-I1", "--crashing-thread-only", "--format", "json"])
            .execute(ctx.withFirebaseHTTP(httpClient(crashed: true)).container))
        #expect(found.warnings.isEmpty)
        #expect(found.data["crashedThreadIndex"]?.int == 1)

        let event = try Envelope(try await ShowCommand.parse(["FB-I1/events/E1", "--crashing-thread-only", "--format", "json"])
            .execute(ctx.withFirebaseHTTP(httpClient(crashed: false)).container))
        #expect(event.warningCodes == ["NO_CRASHED_THREAD"])
    }

    private func singleEventHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(
                    #"{"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS"}"#.utf8))
            }
            #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{
              "eventId":"E1",
              "eventTime":"2026-06-05T12:09:45Z",
              "version":{"displayVersion":"6.16.0","buildVersion":"937"},
              "device":{"model":"iPhone 17 Pro Max"},
              "memory":{"free":"1048576"},
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]
            }]}
            """#.utf8))
        }
    }

    private func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }
}
