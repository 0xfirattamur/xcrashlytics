import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics export")
struct ExportCommandTests {
    private let appId = "1:1234567890:ios:abcdef"
    private let consoleURL = "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.example.app/issues/I1"

    @Test("FB issue Markdown says what the crash is, its windowed impact, where it happens, and the stack")
    func exportsFirebaseIssueMarkdown() async throws {
        let console = SpyConsole()
        let httpClient = firebaseHTTP()
        let cmd = try ExportCommand.parse(["FB-I1"])

        let report = try await cmd.execute(context(httpClient, console: console).container)

        #expect(report.hasPrefix("# [Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)\n"))
        #expect(report.contains(
            "**What:** `FATAL` in `BlurDetectionService.classifyWithML(_:)` — `BlurDetectionService.swift:42`  "))
        #expect(report.contains("**Impact (last 7 days, 1970-01-05 → 1970-01-12):** 1234 events · 56 users (1.00% of 5600)  "))
        #expect(report.contains(
            "**Versions:** first seen 6.2.0 · last seen 6.16.0 (versions of the first and the latest event, not a range)  "))
        #expect(report.contains("| Firebase console | [Open issue](\(consoleURL)) |"))
        #expect(report.contains("Exact counts from the Crashlytics reports over the export window (1970-01-05 → 1970-01-12), top 5 by events."))
        #expect(report.contains(
            "- App versions: 6.16.0 (937) 10 events (66.7%) · 4 users (1.00% of 400); "
                + "6.15.0 (930) 5 events (33.3%) · 2 users (4.00% of 50)"))
        #expect(report.contains("- OS: iOS (26.4.1) 13 events (86.7%) · 5 users; iOS (25.0) 2 events (13.3%) · 1 users"))
        #expect(report.contains(
            "- Devices: iPhone 16 Pro (iPhone17,1) 9 events (60.0%) · 3 users; Apple (iPhone15,2) 6 events (40.0%) · 3 users"))
        #expect(report.contains("**Version range:** 6.15.0 (930) … 6.16.0 (937) (lowest and highest app version with events in the window)  "))
        #expect(!report.contains("sampled events"))
        #expect(report.contains("## Latest occurrence"))
        #expect(report.contains("| Event | `FB-I1/events/E1` |"))
        #expect(report.contains("| App version | 6.16.0 (937) |"))
        #expect(report.contains("BlurDetectionService.classifyWithML(_:) (BlurDetectionService.swift:42)"))
        #expect(!report.contains("raw-user-1"))
        #expect(!report.contains(SHA256Hasher.hexDigest(of: "raw-user-1")))
        #expect(console.outputs == [report])

        let impactQuery = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url?.query)
        // The live API answers 400 INVALID_ARGUMENT to topIssues with filter.issue.id.
        #expect(!impactQuery.contains("filter.issue.id"))
        #expect(impactQuery.contains("filter.interval.startTime=1970-01-05T13:46:40Z"))
        #expect(impactQuery.contains("filter.interval.endTime=1970-01-12T13:46:40Z"))
    }

    @Test("impact pages the window's top issues until the issue appears")
    func impactFindsIssueOnLaterPage() async throws {
        let httpClient = firebaseHTTP { token in token == nil ? Self.otherIssuePage(next: "p1") : Self.issueOnFirstPage }
        let cmd = try ExportCommand.parse(["FB-I1", "--format", "json"])

        let data = try Envelope(try await cmd.execute(context(httpClient).container)).data

        #expect(data["impact"]?["eventsCount"]?.int == 1234)
        let pages = httpClient.requests.filter { $0.url?.path.hasSuffix("/reports/topIssues") == true }
        #expect(pages.count == 2)
        #expect(pages.last?.url?.query?.contains("page_token=p1") == true)
    }

    @Test("an issue absent from every page had no events in the window; past the page cap it is unknown")
    func impactAbsentVersusUnreachable() async throws {
        let absent = try ExportCommand.parse(["FB-I1", "--format", "json"])
        let absentData = try Envelope(try await absent.execute(
            context(firebaseHTTP { _ in Self.otherIssuePage(next: nil) }).container)).data
        #expect(absentData["impact"]?["eventsCount"]?.int == 0)
        #expect(absentData["impact"]?["impactedUsersCount"]?.int == 0)

        let httpClient = firebaseHTTP { _ in Self.otherIssuePage(next: "more") }
        let unreachable = try Envelope(try await absent.execute(context(httpClient).container))
        #expect(unreachable.data["impact"] == nil)
        #expect(unreachable.warningCodes == ["IMPACT_UNAVAILABLE"])
        #expect(httpClient.requests.filter { $0.url?.path.hasSuffix("/reports/topIssues") == true }.count
            == CrashDetailService.impactMaxPages)
    }

    @Test("FB event JSON carries the same report: event occurrence, parent issue, impact, no user ids")
    func exportsFirebaseEventJSON() async throws {
        let cmd = try ExportCommand.parse(["FB-I1/events/E2", "--format", "json", "--since", "30d"])

        let output = try await cmd.execute(context(firebaseHTTP()).container)

        let data = try Envelope(output).data
        #expect(data["id"]?.string == "FB-I1/events/E2")
        #expect(data["issueId"]?.string == "FB-I1")
        #expect(data["crash"]?["file"]?.string == "BlurDetectionService.swift")
        #expect(data["impact"]?["eventsCount"]?.int == 1234)
        #expect(data["impact"]?["since"]?.string == "1969-12-13T13:46:40Z")
        #expect(data["occurrence"]?["id"]?.string == "FB-I1/events/E2")
        #expect(data["occurrence"]?["deviceModel"]?.string == "iPhone 16")
        #expect(data["sample"]?["versionSpread"]?.array?.count == 2)
        #expect(!output.contains("raw-user"))
    }

    @Test("an impact window beyond the Crashlytics 90-day limit fails before any request")
    func rejectsWindowBeyondNinetyDays() async throws {
        let httpClient = firebaseHTTP()
        let cmd = try ExportCommand.parse(["FB-I1", "--since", "120d"])

        await #expect(throws: InvalidInputError.self) {
            try await cmd.execute(context(httpClient).container)
        }
        #expect(httpClient.requests.isEmpty)
    }

    @Test("--since all asks for the 90-day maximum; 90d is accepted; malformed values fail before any request")
    func exportWindows() async throws {
        let httpClient = firebaseHTTP()
        _ = try await ExportCommand.parse(["FB-I1", "--since", "all", "--format", "json"]).execute(context(httpClient).container)
        let query = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true }?.url?.query)
        #expect(query.contains("filter.interval.startTime=1969-10-14T13:46:40Z"))

        let strict = FakeHTTPClient { _ in throw HTTPTransportError.transport("no request expected") }
        for since in ["0d", "-1d", "7x"] {
            await #expect(throws: (any Error).self) {
                _ = try await ExportCommand.parse(["FB-I1", "--since=\(since)"]).execute(context(strict).container)
            }
        }
        #expect(strict.requests.isEmpty)
    }

    @Test("--crashing-thread-only is accepted and warns when the newest event has no crashed thread")
    func exportCrashingThreadOnly() async throws {
        let httpClient = FakeHTTPClient { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/issues/I1") {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"id":"I1","title":"t","errorType":"FATAL"}"#.utf8))
            }
            if path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(Self.issueOnFirstPage.utf8))
            }
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(
                #"{"events":[{"eventId":"E1","threads":[{"crashed":false,"frames":[{"symbol":"idle()"}]}]}]}"#.utf8))
        }
        let env = try Envelope(try await ExportCommand.parse(["FB-I1", "--crashing-thread-only", "--format", "json"])
            .execute(context(httpClient).container))
        #expect(env.warningCodes == ["NO_CRASHED_THREAD"])
    }

    @Test("the issue's newest events are sampled from the export window, not the API's 7-day default")
    func samplesUseExportWindow() async throws {
        let httpClient = firebaseHTTP()
        _ = try await ExportCommand.parse(["FB-I1", "--since", "30d", "--format", "json"]).execute(context(httpClient).container)
        let events = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/events") == true }?.url)
        #expect(events.issuesQueryItem(named: "filter.interval.startTime") == "1969-12-13T13:46:40Z")
        #expect(events.issuesQueryItem(named: "filter.interval.endTime") == "1970-01-12T13:46:40Z")
    }

    @Test("an exported event older than the export window is still found in the 90-day maximum")
    func eventOutsideExportWindow() async throws {
        let httpClient = FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/issues/I1") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"{"id":"I1","title":"t","errorType":"FATAL"}"#.utf8))
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(Self.issueOnFirstPage.utf8))
            }
            if url.path.hasSuffix("/reports/topVersions") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"{"groups":[]}"#.utf8))
            }
            let start = url.issuesQueryItem(named: "filter.interval.startTime") ?? ""
            let wide = start <= "1969-10-14T13:46:40Z"
            return FakeHTTPClient.response(url, status: 200, body: Data(
                (wide ? #"{"events":[{"eventId":"OLD","eventTime":"1969-11-01T00:00:00Z"}]}"# : #"{"events":[]}"#).utf8))
        }
        let output = try await ExportCommand.parse(["FB-I1/events/OLD", "--since", "7d", "--format", "json"])
            .execute(context(httpClient).container)
        #expect(try Envelope(output).data["occurrence"]?["id"]?.string == "FB-I1/events/OLD")
        let eventRequests = httpClient.requests.compactMap(\.url).filter { $0.path.hasSuffix("/events") }
        #expect(eventRequests.count == 2)
    }

    @Test("the exact daily trend comes from topVersions with the issue filter, summed across versions")
    func exportsDailyTrend() async throws {
        let httpClient = firebaseHTTP()
        let report = try await ExportCommand.parse(["FB-I1"]).execute(context(httpClient).container)
        let json = try Envelope(try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(httpClient).container)).data

        #expect(report.contains("**Trend (events per day, UTC):** 1970-01-10: 6 · 1970-01-11: 9  "))
        #expect(json["dailyEvents"]?.array?.compactMap { $0["day"]?.string } == ["1970-01-10", "1970-01-11"])
        #expect(json["dailyEvents"]?.array?.compactMap { $0["eventsCount"]?.int } == [6, 9])
        let request = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topVersions") == true }?.url)
        #expect(request.issuesQueryItem(named: "filter.issue.id") == "I1")
        #expect(request.issuesQueryItem(named: "granularity") == "TIME_GRANULARITY_DAY")
        #expect(request.issuesQueryItem(named: "filter.interval.startTime") == "1970-01-05T13:46:40Z")
    }

    @Test("the crash message is in the What line and the Details table; custom keys, logs and breadcrumbs stay out")
    func exportsCrashMessageOnly() async throws {
        let extras = #"""
        "customKeys":{"crash_info_entry_0":"Swift/Foo.swift:9: Fatal error: Boom","userId":"raw-user-1","feature_flag":"secret-flag"},
        "logs":[{"logTime":"2026-06-10T07:59:00Z","message":"private log line"}],
        "breadcrumbs":[{"eventTime":"2026-06-10T07:58:00Z","title":"private_breadcrumb","params":{"userId":"raw-user-1"}}],
        """#
        let httpClient = firebaseHTTP(eventExtras: extras)
        let report = try await ExportCommand.parse(["FB-I1"]).execute(context(httpClient).container)
        let json = try await ExportCommand.parse(["FB-I1", "--format", "json"]).execute(context(httpClient).container)

        #expect(report.contains(
            "**What:** `FATAL` in `BlurDetectionService.classifyWithML(_:)` — `BlurDetectionService.swift:42` "
                + "— \"Swift/Foo.swift:9: Fatal error: Boom\"  "))
        #expect(report.contains("| Crash message | Swift/Foo.swift:9: Fatal error: Boom |"))
        #expect(try Envelope(json).data["crash"]?["crashMessage"]?.string == "Swift/Foo.swift:9: Fatal error: Boom")
        for leaked in ["secret-flag", "private log line", "private_breadcrumb", "raw-user-1", "feature_flag"] {
            #expect(!report.contains(leaked), "\(leaked)")
            #expect(!json.contains(leaked), "\(leaked)")
        }
    }

    @Test("pipes and newlines in a field cannot break the table")
    func escapesTableCells() async throws {
        let cmd = try ExportCommand.parse(["FB-I1"])

        let report = try await cmd.execute(context(firebaseHTTP(subtitle: "KERN_INVALID_ADDRESS | at 0x0\nsecond line")).container)

        #expect(report.contains("| Subtype | KERN_INVALID_ADDRESS \\| at 0x0 second line |"))
    }

    @Test("--output writes the report to the file and prints only where it went")
    func writesOutputFile() async throws {
        let console = SpyConsole()
        let ctx = try context(firebaseHTTP(), console: console)
        let path = "/tmp/xcrashlytics-export-test/crash.md"
        let cmd = try ExportCommand.parse(["FB-I1", "--output", path])

        let report = try await cmd.execute(ctx.container)

        let written = try #require(String(bytes: ctx.fileStore.readData(at: path), encoding: .utf8))
        #expect(written == report)
        #expect(console.outputs == ["Exported FB-I1 to \(path).\n"])
    }

    @Test("--output prints stderr warnings before writing, so a failed write keeps them")
    func warningsSurviveFailedWrite() async throws {
        let base = InMemoryFileStore()
        let crashDir = "/tmp/xcrashlytics-export-test/crashes"
        let fixture = Bundle.module.url(forResource: "sample.crash", withExtension: nil, subdirectory: "Fixtures")!
        base.seed("\(crashDir)/A.crash", text: try String(contentsOf: fixture, encoding: .utf8))
        base.seed("\(crashDir)/broken.crash", text: "This is not a crash log.")
        let console = SpyConsole()
        let ctx = Platform.testing(
            fileStore: AtomicWriteFailingFileStore(base: base), subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(), console: console)
        let cmd = try ExportCommand.parse([
            "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "--crash-directory", crashDir, "--output", "/tmp/out.md"
        ])

        await #expect(throws: AtomicWriteFailingFileStore.Failure.self) { _ = try await cmd.execute(ctx.container) }

        #expect(console.warnings.count == 1)
        #expect(console.warnings.first?.hasPrefix("XCODE_PARSE_FAILED: ") == true)
        #expect(console.outputs.isEmpty)
    }

    @Test("XC export names the first symbolicated app frame as the culprit and has no impact section")
    func exportsXcodeCrash() async throws {
        let fileStore = InMemoryFileStore()
        let crashDir = "/tmp/xcrashlytics-export-test/crashes"
        let fixture = Bundle.module.url(forResource: "sample.crash", withExtension: nil, subdirectory: "Fixtures")!
        fileStore.seed("\(crashDir)/A.crash", text: try String(contentsOf: fixture, encoding: .utf8))
        let ctx = Platform.testing(fileStore: fileStore, subprocessExecutor: StubSubprocessExecutor(), dateProvider: FixedDateProvider())
        let cmd = try ExportCommand.parse([
            "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "--crash-directory", crashDir
        ])

        let report = try await cmd.execute(ctx.container)

        #expect(report.hasPrefix("# EXC_BAD_ACCESS\n"))
        #expect(report.contains("**What:** `EXC_BAD_ACCESS` (SIGSEGV) in `-[ExampleViewController crashNow]`  "))
        #expect(report.contains("## Occurrence"))
        #expect(report.contains("| Device | iPhone14,2 |"))
        #expect(!report.contains("**Impact"))
        #expect(!report.contains("## Where it happens"))
    }

    @Test("a non-fatal's culprit is the app code that recorded it, not the Crashlytics SDK frames above it")
    func nonFatalCulpritSkipsCrashlyticsRecording() {
        let issue = CrashIssue(
            providerId: "I1",
            title: "[Core] FIRCLSNonFatalError.m - -[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]",
            exceptionType: "NON_FATAL")
        let frames = [
            StackFrame(index: 0, binaryName: "Core", symbol: "-[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]",
                  file: "FIRCLSNonFatalError.m", line: 33, isSymbolicated: true),
            StackFrame(index: 1, binaryName: "Core", symbol: "-[FIRCrashlytics recordError:userInfo:]",
                  file: "FIRCrashlytics.m", line: 435, isSymbolicated: true),
            StackFrame(index: 2, binaryName: "Core", symbol: "BlurMLClassifier.recordFailure(error:message:)",
                  file: "BlurMLClassifier.swift", line: 186, isSymbolicated: true)
        ]
        let event = CrashEvent(
            id: issue.id, source: .firebase, crashedThreadIndex: 0, exception: issue.exception, frames: frames)

        let report = exportReport(event, issue, toolVersion: "test")

        #expect(report.crash.file == "BlurMLClassifier.swift")
        #expect(report.crash.symbol == "BlurMLClassifier.recordFailure(error:message:)")
        #expect(report.crash.topSourceFrame?.line == 186)
        #expect(report.frames.count == 3)
    }

    private func exportReport(_ event: CrashEvent, _ issue: CrashIssue, toolVersion: String) -> ExportReport {
        let detail = CrashDetail(event: event, issue: issue)
        let result = CrashExportResult(detail: detail, exportedAt: Date(), window: DateInterval(), warnings: [])
        return ExportReport(result, toolVersion: toolVersion)
    }

    func context(_ httpClient: FakeHTTPClient, console: SpyConsole = SpyConsole()) throws -> Platform {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider(),
            console: console
        ).withFirebaseHTTP(httpClient)
    }

    private static let issueOnFirstPage = #"""
    {"groups":[{"issue":{"id":"I1"},"metrics":[{"eventsCount":"1234","impactedUsersCount":"56","totalUsersCount":"5600"}]}]}
    """#

    private static func otherIssuePage(next: String?) -> String {
        let token = next.map { #","nextPageToken":"\#($0)""# } ?? ""
        return #"{"groups":[{"issue":{"id":"OTHER"},"metrics":[{"eventsCount":"9","totalUsersCount":"5600"}]}]\#(token)}"#
    }

    /// Two versions, each with the whole-window total first and then one point per UTC day.
    private static let dailyVersionsReport = #"""
    {"groups":[
      {"version":{"displayVersion":"6.16.0","buildVersion":"937","displayName":"6.16.0 (937)"},
       "metrics":[
         {"eventsCount":"10","impactedUsersCount":"4","totalUsersCount":"400","startTime":"1970-01-05T13:46:40Z","endTime":"1970-01-12T13:46:40Z"},
         {"eventsCount":"6","startTime":"1970-01-10T00:00:00Z","endTime":"1970-01-11T00:00:00Z"},
         {"eventsCount":"4","startTime":"1970-01-11T00:00:00Z","endTime":"1970-01-12T00:00:00Z"}]},
      {"version":{"displayVersion":"6.15.0","buildVersion":"930","displayName":"6.15.0 (930)"},
       "metrics":[
         {"eventsCount":"5","impactedUsersCount":"2","totalUsersCount":"50","startTime":"1970-01-05T13:46:40Z","endTime":"1970-01-12T13:46:40Z"},
         {"eventsCount":"5","startTime":"1970-01-11T00:00:00Z","endTime":"1970-01-12T00:00:00Z"}]}
    ]}
    """#

    private static let osReport = #"""
    {"groups":[
      {"operatingSystem":{"displayVersion":"26.4.1","os":"iOS","displayName":"iOS (26.4.1)"},
       "metrics":[{"eventsCount":"13","impactedUsersCount":"5","totalUsersCount":"5"}]},
      {"operatingSystem":{"displayVersion":"25.0","os":"iOS","displayName":"iOS (25.0)"},
       "metrics":[{"eventsCount":"2","impactedUsersCount":"1","totalUsersCount":"1"}]}]}
    """#

    private static let devicesReport = #"""
    {"groups":[{"device":{"manufacturer":"Apple","displayName":"Apple"},"metrics":[{"eventsCount":"15"}],
      "subgroups":[
       {"device":{"manufacturer":"Apple","model":"iPhone17,1","displayName":"Apple (iPhone17,1)","marketingName":"iPhone 16 Pro"},
        "metrics":[{"eventsCount":"9","impactedUsersCount":"3"}]},
       {"device":{"manufacturer":"Apple","model":"iPhone15,2","displayName":"Apple (iPhone15,2)"},
        "metrics":[{"eventsCount":"6","impactedUsersCount":"3"}]}]}]}
    """#

    /// `topIssuesPages(pageToken)` answers each topIssues page; the token is nil for the first page.
    /// `eventExtras` are extra JSON members of the newest event (end each with a comma).
    func firebaseHTTP(
        subtitle: String? = nil,
        eventExtras: String = "",
        failingReports: Set<String> = [],
        topIssuesPages: @escaping @Sendable (String?) -> String = { _ in issueOnFirstPage }
    ) -> FakeHTTPClient {
        var issue: [String: Any] = [
            "id": "I1",
            "title": "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
            "errorType": "FATAL",
            "firstSeenVersion": "6.2.0",
            "lastSeenVersion": "6.16.0",
            "uri": consoleURL
        ]
        issue["subtitle"] = subtitle
        let issueBody = (try? JSONSerialization.data(withJSONObject: issue)) ?? Data()
        return FakeHTTPClient { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/issues/I1") {
                return FakeHTTPClient.response(request.url!, status: 200, body: issueBody)
            }
            if let failing = failingReports.first(where: { path.hasSuffix("/reports/\($0)") }) {
                return FakeHTTPClient.response(
                    request.url!, status: 400, body: Data(#"{"error":{"message":"\#(failing) is down"}}"#.utf8))
            }
            if path.hasSuffix("/reports/topVersions") {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(Self.dailyVersionsReport.utf8))
            }
            if path.hasSuffix("/reports/topOperatingSystems") {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(Self.osReport.utf8))
            }
            if path.hasSuffix("/reports/topAppleDevices") {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(Self.devicesReport.utf8))
            }
            if path.hasSuffix("/reports/topIssues") {
                let token = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "page_token" }?.value
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(topIssuesPages(token).utf8))
            }
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E1","eventTime":"2026-06-10T08:00:00Z",
               "version":{"displayVersion":"6.16.0","buildVersion":"937"},
               "device":{"model":"iPhone 17 Pro Max"},
               "platform":"IOS","operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"raw-user-1"},
               \#(eventExtras)
               "threads":[{"crashed":true,"frames":[
                 {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core",
                  "file":"BlurDetectionService.swift","line":"42","blamed":true}
               ]}]},
              {"eventId":"E2","eventTime":"2026-06-01T08:00:00Z",
               "version":{"displayVersion":"6.15.0","buildVersion":"930"},
               "device":{"model":"iPhone 16"},
               "platform":"IOS","operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"raw-user-2"},
               "threads":[{"crashed":true,"frames":[
                 {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core",
                  "file":"BlurDetectionService.swift","line":"42","blamed":true}
               ]}]}
            ]}
            """#.utf8))
        }
    }
}

/// Delegates everything except atomic writes, which fail like a read-only destination.
private final class AtomicWriteFailingFileStore: FileStore, @unchecked Sendable {
    struct Failure: Error {}

    private let base: FileStore

    init(base: FileStore) { self.base = base }

    func exists(at path: String) -> Bool { base.exists(at: path) }
    func readData(at path: String) throws -> Data { try base.readData(at: path) }
    func writeDataAtomically(_ data: Data, to path: String) throws { throw Failure() }
    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] {
        try base.listFiles(under: path, withExtensions: extensions)
    }
    func attributes(at path: String) throws -> FileAttributes { try base.attributes(at: path) }
}
