import Foundation
import Testing
@testable import xcrashlytics

/// Every events request carries an explicit interval: without one the API reaches back only about 7 days.
@Suite("event request windows")
struct EventWindowTests {
    private let appId = "1:1234567890:ios:abcdef"
    /// `FixedDateProvider`'s default now is 1_000_000s after the epoch.
    private let ninetyDayStart = "1969-10-14T13:46:40Z"
    private let now = "1970-01-12T13:46:40Z"

    private func config() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    private func recordingHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/issues/I1") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"{"id":"I1","title":"t","errorType":"FATAL"}"#.utf8))
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"groups":[{"issue":{"id":"I1","title":"t","errorType":"FATAL"},"metrics":[{"eventsCount":"3"}]}]}
                """#.utf8))
            }
            return FakeHTTPClient.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E1","eventTime":"1969-11-01T00:00:00Z",
              "threads":[{"crashed":true,"frames":[{"symbol":"f()","library":"App","file":"F.swift","line":"3","blamed":true}]}]}]}
            """#.utf8))
        }
    }

    private func eventURLs(_ httpClient: FakeHTTPClient) -> [URL] {
        httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/events") }
    }

    private func expectNinetyDays(_ urls: [URL], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!urls.isEmpty, sourceLocation: sourceLocation)
        for url in urls {
            #expect(url.issuesQueryItem(named: "filter.interval.startTime") == ninetyDayStart, sourceLocation: sourceLocation)
            #expect(url.issuesQueryItem(named: "filter.interval.endTime") == now, sourceLocation: sourceLocation)
        }
    }

    @Test("show samples the issue's newest 100 events from the 90-day maximum")
    func showWindow() async throws {
        let httpClient = recordingHTTP()
        let ctx = Platform.testing(fileStore: try config(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let output = try await ShowCommand.parse(["FB-I1", "--format", "json"]).execute(ctx.withFirebaseHTTP(httpClient).container)

        expectNinetyDays(eventURLs(httpClient))
        #expect(eventURLs(httpClient).first?.issuesQueryItem(named: "page_size") == "100")
        #expect(try Envelope(output).data["frames"]?[0]?["symbol"]?.string == "f()")
    }

    @Test("open reads the newest event from the 90-day maximum")
    func openWindow() async throws {
        let httpClient = recordingHTTP()
        let fileStore = try config()
        fileStore.seed("\(FileManager.default.currentDirectoryPath)/Sources/F.swift", text: "// source")
        let ctx = Platform.testing(
            fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor { _, _ in SubprocessResult(exitCode: 0, standardOutput: "", standardError: "") },
            dateProvider: FixedDateProvider())
        _ = try await OpenCommand.parse(["FB-I1"]).execute(ctx.withFirebaseHTTP(httpClient).container)

        expectNinetyDays(eventURLs(httpClient))
    }

    @Test("blame samples events from the report window")
    func blameWindow() async throws {
        let httpClient = recordingHTTP()
        let ctx = Platform.testing(fileStore: try config(), subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        _ = try await BlameCommand.parse(["--since", "30d", "--format", "json"]).execute(ctx.withFirebaseHTTP(httpClient).container)

        let url = try #require(eventURLs(httpClient).first)
        #expect(url.issuesQueryItem(named: "filter.interval.startTime") == "1969-12-13T13:46:40Z")
        #expect(url.issuesQueryItem(named: "filter.interval.endTime") == now)
    }
}
