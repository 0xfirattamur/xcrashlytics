import Foundation
import Testing
@testable import xcrashlytics

/// `events`: --since scans, --user-id depth, flag validation, and crashing-thread warnings.
@Suite("xcrashlytics events investigation")
struct EventsInvestigationTests {
    private let appId = "1:1234567890:ios:abcdef"
    private let now = ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z")!

    private func context(_ httpClient: FakeHTTPClient) throws -> Platform {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(now)).withFirebaseHTTP(httpClient
        )
    }

    /// An endless, newest-first event stream of `total` events, served in the requested page size.
    private func stream(total: Int, time: @escaping (Int) -> String, user: @escaping (Int) -> String = { "u\($0)" }) -> FakeHTTPClient {
        FakeHTTPClient { request in
            let url = request.url!
            let size = Int(url.issuesQueryItem(named: "page_size") ?? "100") ?? 100
            let start = Int(url.issuesQueryItem(named: "page_token") ?? "0") ?? 0
            let end = min(total, start + size)
            let events = (start..<end).map { #"{"eventId":"E\#($0)","eventTime":"\#(time($0))","user":{"id":"\#(user($0))"}}"# }
            let next = end < total ? #","nextPageToken":"\#(end)""# : ""
            return FakeHTTPClient.response(url, status: 200, body: Data("{\"events\":[\(events.joined(separator: ","))]\(next)}".utf8))
        }
    }

    private func eventRequests(_ httpClient: FakeHTTPClient) -> [URL] {
        httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/events") }
    }

    private func failureCode(_ args: [String]) async throws -> String? {
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.transport("no request expected") }
        do {
            _ = try await EventsCommand.parse(args + ["--format", "json"]).execute(context(httpClient).container)
            return nil
        } catch {
            #expect(httpClient.requests.isEmpty, "\(args) must fail before any request")
            return CommandRunner.failure(for: error).code
        }
    }

    // MARK: - --since

    @Test("--since is a server-side interval: the request carries it, and no deep scan happens")
    func sinceIsServerSideInterval() async throws {
        let httpClient = stream(total: 4, time: { _ in "2026-06-07T12:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--since", "24h", "--format", "json"]).execute(context(httpClient).container)

        let data = try Envelope(output).data
        #expect(data["events"]?.array?.count == 4)
        let requests = eventRequests(httpClient)
        #expect(requests.count == 1)
        #expect(requests.first?.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-07T00:00:00Z")
        #expect(requests.first?.issuesQueryItem(named: "filter.interval.endTime") == "2026-06-08T00:00:00Z")
        #expect(requests.first?.issuesQueryItem(named: "page_size") == "10")
        #expect(data["scanDepth"] == nil)
        #expect(data["scannedEvents"] == nil)
    }

    @Test("without --since events are requested from the 90-day maximum, so old events are reached")
    func defaultWindowIsNinetyDays() async throws {
        let httpClient = stream(total: 2, time: { _ in "2026-04-01T00:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"]).execute(context(httpClient).container)

        let request = try #require(eventRequests(httpClient).first)
        #expect(request.issuesQueryItem(named: "filter.interval.startTime") == "2026-03-10T00:00:00Z")
        #expect(request.issuesQueryItem(named: "filter.interval.endTime") == "2026-06-08T00:00:00Z")
        #expect(try Envelope(output).data["events"]?.array?.count == 1)
    }

    @Test("--since all is the 90-day window: one request of --limit events, no truncation warning")
    func sinceAllIsMaximumWindow() async throws {
        let httpClient = stream(total: 5_000, time: { _ in "2020-01-01T00:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--since", "all", "--limit", "3", "--format", "json"])
            .execute(context(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["events"]?.array?.count == 3)
        #expect(eventRequests(httpClient).count == 1)
        #expect(eventRequests(httpClient).first?.issuesQueryItem(named: "page_size") == "3")
        #expect(eventRequests(httpClient).first?.issuesQueryItem(named: "filter.interval.startTime") == "2026-03-10T00:00:00Z")
        #expect(env.warnings.isEmpty)
        #expect(env.data["scanDepth"] == nil)
    }

    @Test("--since with --user-id scans 50 events inside the window and warns when they all fell short")
    func userIdScanInsideWindow() async throws {
        let httpClient = stream(total: 5_000, time: { _ in "2026-06-07T12:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--since", "7d", "--user-id", "nobody", "--format", "json"])
            .execute(context(httpClient).container)

        let env = try Envelope(output)
        #expect(env.warningCodes == ["SCAN_TRUNCATED"])
        #expect(env.data["scanDepth"]?.int == 50)
        #expect(env.data["scannedEvents"]?.int == 50)
        #expect(env.warnings.first?["message"]?.string?.contains("in the window") == true)
        #expect(eventRequests(httpClient).allSatisfy {
            $0.issuesQueryItem(named: "filter.interval.startTime") == "2026-06-01T00:00:00Z"
        })
    }

    @Test("--user-id that read the whole window without a match does not warn")
    func userIdWindowExhausted() async throws {
        let httpClient = stream(total: 20, time: { _ in "2026-06-07T12:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--since", "7d", "--user-id", "nobody", "--format", "json"])
            .execute(context(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["events"]?.array?.isEmpty == true)
        #expect(env.data["scannedEvents"]?.int == 20)
        #expect(env.warnings.isEmpty)
    }

    @Test("a filled --limit with --since never warns")
    func noWarningWhenLimitFilled() async throws {
        let httpClient = stream(total: 5_000, time: { _ in "2026-06-07T12:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--since", "7d", "--limit", "5", "--format", "json"])
            .execute(context(httpClient).container)
        let env = try Envelope(output)
        #expect(env.data["events"]?.array?.count == 5)
        #expect(env.warnings.isEmpty)
    }

    @Test("--since values that are not positive durations are BAD_INPUT before any request")
    func invalidSince() async throws {
        for since in ["7x", "0d", "-1d", "1e3m", "d"] {
            let code = try await failureCode(["FB-I1", "--since=\(since)"])
            #expect(code == "BAD_INPUT", "--since \(since) -> \(code ?? "nil")")
        }
    }

    // MARK: - --user-id depth

    @Test("--user-id scans 50 events per issue, reports the depth, and warns when --limit was not met")
    func userIdScanWarning() async throws {
        let httpClient = stream(total: 500, time: { _ in "2026-06-07T12:00:00Z" })
        let output = try await EventsCommand.parse(["FB-I1", "--user-id", "nobody", "--limit", "3", "--format", "json"])
            .execute(context(httpClient).container)

        let env = try Envelope(output)
        #expect(env.data["scannedEvents"]?.int == 50)
        #expect(env.data["scanDepth"]?.int == 50)
        #expect(env.warningCodes == ["SCAN_TRUNCATED"])
    }

    @Test("--user-id with enough matches does not warn")
    func userIdSatisfied() async throws {
        let httpClient = stream(total: 500, time: { _ in "2026-06-07T12:00:00Z" }, user: { $0 % 2 == 0 ? "me" : "other" })
        let output = try await EventsCommand.parse(["FB-I1", "--user-id", "me", "--limit", "3", "--format", "json"])
            .execute(context(httpClient).container)
        let env = try Envelope(output)
        #expect(env.data["events"]?.array?.count == 3)
        #expect(env.warnings.isEmpty)
    }

    // MARK: - Flags

    @Test("--limit must be positive and cannot be combined with --latest")
    func limitValidation() async throws {
        #expect(try await failureCode(["FB-I1", "--limit", "0"]) == "BAD_INPUT")
        #expect(try await failureCode(["FB-I1", "--limit=-2"]) == "BAD_INPUT")
        #expect(try await failureCode(["FB-I1", "--latest", "--limit", "3"]) == "BAD_INPUT")
        #expect(try await failureCode(["FB-I1", "--user-id", " "]) == "BAD_INPUT")
        #expect(try await failureCode([]) == "BAD_INPUT")
    }

    // MARK: - Crashing thread

    private func threadsHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            let body = #"""
            {"events":[
              {"eventId":"CRASHED","eventTime":"2026-06-07T12:00:00Z","platform":"ANDROID","operatingSystem":{"displayVersion":"15"},
               "threads":[{"crashed":false,"frames":[{"symbol":"idle()"}]},{"crashed":true,"frames":[{"symbol":"boom()"}]}]},
              {"eventId":"NONE","eventTime":"2026-06-07T11:00:00Z",
               "threads":[{"crashed":false,"frames":[{"symbol":"idle()"}]}]}
            ]}
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    @Test("--crashing-thread-only warns NO_CRASHED_THREAD per event without a crashed thread; default listing does not")
    func crashingThreadWarning() async throws {
        let output = try await EventsCommand.parse(["FB-I1", "--crashing-thread-only", "--format", "json"])
            .execute(context(threadsHTTP()).container)
        let env = try Envelope(output)
        #expect(env.warningCodes == ["NO_CRASHED_THREAD"])
        #expect(env.warnings.first?["message"]?.string?.contains("FB-I1/events/NONE") == true)

        let plain = try await EventsCommand.parse(["FB-I1", "--frames-only", "--format", "json"])
            .execute(context(threadsHTTP()).container)
        #expect(try Envelope(plain).warnings.isEmpty)
    }

    @Test("the OS label follows the event platform")
    func osLabelFromPlatform() async throws {
        let text = try await EventsCommand.parse(["FB-I1"]).execute(context(threadsHTTP()).container)
        #expect(text.contains("Android 15"))
        #expect(!text.contains("iOS 15"))
    }
}
