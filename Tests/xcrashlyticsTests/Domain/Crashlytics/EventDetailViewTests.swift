import Foundation
import Testing
@testable import xcrashlytics

/// Crash message, custom keys, logs, crashed thread and breadcrumbs of Firebase events,
/// and the promise that no raw user id is ever printed.
@Suite("event detail")
struct EventDetailViewTests {
    private let appId = "1:1234567890:ios:abcdef"
    private let userId = "user-ABC-123"

    private var eventJSON: String {
        #"""
        {"eventId":"E1","eventTime":"2026-06-10T08:00:00Z","user":{"id":"\#(userId)"},
         "customKeys":{
           "crash_info_entry_10":"tenth",
           "crash_info_entry_1":"second entry",
           "crash_info_entry_0":"Object deallocated\nFoo.swift:77: Fatal error: Array index out of range",
           "userId":"\#(userId)","UID":"u-1","user_id":"u-2",
           "feature":"on","owner":"\#(userId)","note":"seen for \#(userId) today"},
         "logs":[{"logTime":"2026-06-10T07:59:00Z","message":"opened screen for \#(userId)"}],
         "breadcrumbs":[{"eventTime":"2026-06-10T07:58:00Z","title":"tap",
           "params":{"userId":"\#(userId)","screen":"home","who":"\#(userId)","count":3}}],
         "threads":[{"title":"Thread"},
           {"crashed":true,"title":"Crashed: com.apple.main-thread","subtitle":"SIGABRT ABORT 0x1",
            "signal":"SIGABRT","signalCode":"ABORT","crashAddress":9806368972,"queue":"com.apple.main-thread",
            "frames":[{"symbol":"f()","file":"Foo.swift","line":"77","library":"App","blamed":true}]}]}
        """#
    }

    private func decode(_ json: String) throws -> CrashlyticsEvent {
        let data = Data(#"{"events":[\#(json)]}"#.utf8)
        return CrashlyticsEventDTOMapper().event(from: try #require(CrashlyticsDTO.EventsResponse.decodePreservingRawEvents(from: data).events.first))
    }

    // MARK: - EventDetailView

    @Test("crash info entries come in index order, not string order, and the message is the failure line")
    func crashInfoAndMessage() throws {
        let view = EventDetailView(try decode(eventJSON))
        #expect(view.crashInfo == [
            "Object deallocated\nFoo.swift:77: Fatal error: Array index out of range", "second entry", "tenth"
        ])
        #expect(view.crashMessage == "Foo.swift:77: Fatal error: Array index out of range")
    }

    @Test("Precondition and Assertion failures count as the crash message; several lines are all kept")
    func failureMarkers() throws {
        let event = CrashlyticsEvent(customKeys: [
            "crash_info_entry_0": "a\nPrecondition failed: nope",
            "crash_info_entry_1": "Assertion failed: also\nunrelated"
        ])
        #expect(EventDetailView(event).crashMessage == "Precondition failed: nope\nAssertion failed: also")
    }

    @Test("without a failure marker the message is the last entry's last line; no entries means no message")
    func fallbackMessage() {
        let withEntries = CrashlyticsEvent(customKeys: [
            "crash_info_entry_0": "first", "crash_info_entry_1": "line one\nline two\n"
        ])
        #expect(EventDetailView(withEntries).crashMessage == "line two")
        let none = EventDetailView(CrashlyticsEvent(customKeys: ["feature": "on"]))
        #expect(none.crashInfo == nil)
        #expect(none.crashMessage == nil)
    }

    @Test("custom keys drop crash_info entries, user-id keys in any case, and values equal to the user id")
    func customKeysRedacted() throws {
        let view = EventDetailView(try decode(eventJSON))
        #expect(view.customKeys == ["feature": "on", "note": "seen for [redacted] today"])
    }

    @Test("log messages blank the user id")
    func logsRedacted() throws {
        let view = EventDetailView(try decode(eventJSON))
        #expect(view.logs == [.init(time: "2026-06-10T07:59:00Z", message: "opened screen for [redacted]")])
    }

    @Test("the crashed thread carries title, signal, signal code, crash address and queue")
    func crashedThread() throws {
        let view = EventDetailView(try decode(eventJSON))
        #expect(view.crashedThread == .init(
            title: "Crashed: com.apple.main-thread", signal: "SIGABRT", signalCode: "ABORT",
            crashAddress: "9806368972", queue: "com.apple.main-thread"))
        #expect(EventDetailView(CrashlyticsEvent(threads: [CrashlyticsThread(title: "t")])).crashedThread == nil)
    }

    @Test("breadcrumbs appear only on request, with user-id params removed")
    func breadcrumbsOptIn() throws {
        let event = try decode(eventJSON)
        #expect(EventDetailView(event).breadcrumbs == nil)
        let crumbs = try #require(EventDetailView(event, includeBreadcrumbs: true).breadcrumbs)
        #expect(crumbs == [.init(time: "2026-06-10T07:58:00Z", title: "tap", params: ["screen": "home", "count": "3"])])
    }

    @Test("an event without a user id still hides user-id keys")
    func noEventUserId() {
        let event = CrashlyticsEvent(customKeys: ["userId": "anyone", "mode": "x"])
        #expect(EventDetailView(event).customKeys == ["mode": "x"])
    }

    @Test("custom keys given as a [{key, value}] list decode, and --user-info-key matching still sees them")
    func listShapedCustomKeys() throws {
        let event = try decode(#"{"eventId":"E1","customKeys":[{"key":"feature","value":"on"}]}"#)
        #expect(event.customKeys == ["feature": "on"])
        #expect(CrashlyticsEventMetadataReader(event).matchesUserInfoFilter("feature=on"))
    }

    // MARK: - events command

    private func context(_ httpClient: FakeHTTPClient) throws -> Platform {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()).withFirebaseHTTP(httpClient
        )
    }

    private func eventsHTTP() -> FakeHTTPClient {
        let body = Data(#"{"events":[\#(eventJSON)]}"#.utf8)
        return FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Array crash","errorType":"FATAL","firstSeenVersion":"6.22.0","lastSeenVersion":"5.3.1"}
                """#.utf8))
            }
            return FakeHTTPClient.response(request.url!, status: 200, body: body)
        }
    }

    @Test("events JSON has crash info, message, custom keys, logs and crashed thread, and never the raw user id")
    func eventsJSON() async throws {
        let output = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"])
            .execute(context(eventsHTTP()).container)

        let event = try #require(try Envelope(output).data["events"]?[0])
        #expect(event["crashMessage"]?.string == "Foo.swift:77: Fatal error: Array index out of range")
        #expect(event["crashInfo"]?.array?.count == 3)
        #expect(event["customKeys"]?["feature"]?.string == "on")
        #expect(event["customKeys"]?["crash_info_entry_0"] == nil)
        #expect(event["logs"]?[0]?["message"]?.string == "opened screen for [redacted]")
        #expect(event["crashedThread"]?["signal"]?.string == "SIGABRT")
        #expect(event["crashedThread"]?["queue"]?.string == "com.apple.main-thread")
        #expect(event["breadcrumbs"] == nil)
        #expect(event["userIdHash"]?.string == SHA256Hasher.hexDigest(of: userId))
        #expect(!output.contains(userId))
    }

    @Test("--breadcrumbs adds redacted breadcrumbs to events JSON and ndjson")
    func eventsBreadcrumbs() async throws {
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--breadcrumbs", "--format", "json"])
            .execute(context(eventsHTTP()).container)
        let crumbs = try #require(try Envelope(json).data["events"]?[0]?["breadcrumbs"]?.array)
        #expect(crumbs.count == 1)
        #expect(crumbs[0]["title"]?.string == "tap")
        #expect(crumbs[0]["params"]?["screen"]?.string == "home")
        #expect(crumbs[0]["params"]?["userId"] == nil)
        #expect(!json.contains(userId))

        let ndjson = try await EventsCommand.parse(["FB-I1", "--latest", "--breadcrumbs", "--format", "ndjson"])
            .execute(context(eventsHTTP()).container)
        #expect(try JSON.lines(ndjson).first?["breadcrumbs"]?.array?.count == 1)
        #expect(!ndjson.contains(userId))
    }

    @Test("frames-only output keeps the crash message and crashed thread but not custom keys, logs or breadcrumbs")
    func eventsFramesOnly() async throws {
        let output = try await EventsCommand.parse(["FB-I1", "--latest", "--frames-only", "--breadcrumbs", "--format", "json"])
            .execute(context(eventsHTTP()).container)

        let event = try #require(try Envelope(output).data["events"]?[0])
        #expect(event["crashMessage"]?.string == "Foo.swift:77: Fatal error: Array index out of range")
        #expect(event["crashedThread"]?["signal"]?.string == "SIGABRT")
        #expect(event["customKeys"] == nil)
        #expect(event["logs"] == nil)
        #expect(event["breadcrumbs"] == nil)
        #expect(!output.contains(userId))
    }

    @Test("events text prints the crash message under the event row")
    func eventsText() async throws {
        let output = try await EventsCommand.parse(["FB-I1", "--latest"]).execute(context(eventsHTTP()).container)
        #expect(output.contains("crash: Foo.swift:77: Fatal error: Array index out of range"))
        #expect(!output.contains(userId))

        let frames = try await EventsCommand.parse(["FB-I1", "--latest", "--frames-only"])
            .execute(context(eventsHTTP()).container)
        #expect(frames.contains("crash: Foo.swift:77: Fatal error: Array index out of range"))
    }

    // MARK: - show

    @Test("show JSON carries the event detail fields; breadcrumbs only with --breadcrumbs")
    func showJSON() async throws {
        let plain = try await ShowCommand.parse(["FB-I1", "--format", "json"]).execute(context(eventsHTTP()).container)
        let data = try Envelope(plain).data
        #expect(data["crashMessage"]?.string == "Foo.swift:77: Fatal error: Array index out of range")
        #expect(data["customKeys"]?["feature"]?.string == "on")
        #expect(data["logs"]?[0]?["message"]?.string == "opened screen for [redacted]")
        #expect(data["crashedThread"]?["title"]?.string == "Crashed: com.apple.main-thread")
        #expect(data["breadcrumbs"] == nil)
        #expect(!plain.contains(userId))

        let withCrumbs = try await ShowCommand.parse(["FB-I1/events/E1", "--breadcrumbs", "--format", "json"])
            .execute(context(eventsHTTP()).container)
        #expect(try Envelope(withCrumbs).data["breadcrumbs"]?.array?.count == 1)
        #expect(!withCrumbs.contains(userId))
    }

    @Test("show text prints the crash message and says first seen / last seen, not a range")
    func showText() async throws {
        let output = try await ShowCommand.parse(["FB-I1"]).execute(context(eventsHTTP()).container)
        #expect(output.contains("Crash:     Foo.swift:77: Fatal error: Array index out of range"))
        #expect(output.contains("Versions:  first seen 6.22.0 · last seen 5.3.1"))
        #expect(!output.contains(userId))
    }
}
