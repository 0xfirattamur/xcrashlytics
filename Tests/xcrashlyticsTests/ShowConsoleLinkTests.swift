import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics show <console link>")
struct ShowConsoleLinkTests {
    private let releaseAppId = "1:1234567890:ios:release"

    private func link(_ query: String = "") -> String {
        "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues/I1" + query
    }

    /// Debug is active; the link points at the release app.
    private func context(requests: RequestLog) throws -> CommandContext {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(activeProfile: "debug", profiles: [
            "debug": AppProfile(appId: "1:1234567890:ios:debug", bundleId: "com.x.app.debug"),
            "release": AppProfile(appId: releaseAppId, bundleId: "com.x.app"),
        ]))
        let http = MockHTTPTransport { request in
            requests.append(request.url!)
            if request.url!.path.hasSuffix("/issues/I1") {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(
                    #"{"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS"}"#.utf8))
            }
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E-NEW","threads":[{"crashed":true,"frames":[{"symbol":"newest()","library":"App"}]}]},
              {"eventId":"E-OLD","device":{"model":"iPhone15,2"},
               "threads":[{"crashed":true,"frames":[{"symbol":"linked()","library":"App"}]}]}
            ]}
            """#.utf8))
        }
        return CommandContext(fileSystem: fs, processRunner: MockProcessRunner(), clock: FixedClock())
            .withFirebaseHTTP(http)
    }

    @Test("queries the app whose profile matches the link, not the active one")
    func usesMatchingProfile() async throws {
        let requests = RequestLog()
        let cmd = try ShowCommand.parse([link(), "--format", "json"])

        let data = try Envelope(try await cmd.runWithContext(try context(requests: requests))).data

        #expect(data["id"]?.string == "FB-I1")
        let firebasePaths = requests.urls.map(\.path).filter { $0.contains("/apps/") }
        #expect(!firebasePaths.isEmpty)
        #expect(firebasePaths.allSatisfy { $0.contains("/apps/\(releaseAppId)/") })
    }

    @Test("sessionEventKey selects the linked event, not the newest")
    func resolvesSessionEvent() async throws {
        let cmd = try ShowCommand.parse([link("?sessionEventKey=E-OLD_1662682800563319436"), "--format", "json"])

        let env = try Envelope(try await cmd.runWithContext(try context(requests: RequestLog())))

        #expect(env.data["id"]?.string == "FB-I1/events/E-OLD")
        #expect(env.data["deviceModel"]?.string == "iPhone15,2")
        #expect(env.data["frames"]?[0]?["symbol"]?.string == "linked()")
        #expect(env.warnings.isEmpty)
    }

    @Test("an unresolvable event key falls back to the issue with a warning")
    func unresolvedEventWarns() async throws {
        let cmd = try ShowCommand.parse([link("?sessionEventKey=MISSING_1"), "--format", "json"])

        let env = try Envelope(try await cmd.runWithContext(try context(requests: RequestLog())))

        #expect(env.data["id"]?.string == "FB-I1")
        #expect(env.warningCodes == ["EVENT_NOT_RESOLVED"])
    }

    @Test("a link for an unconfigured app fails before any Firebase request")
    func unknownAppFails() async throws {
        let requests = RequestLog()
        let other = "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.other/issues/I1"
        let cmd = try ShowCommand.parse([other, "--format", "json"])
        let ctx = try context(requests: requests)

        await #expect(throws: (any Error).self) { _ = try await cmd.runWithContext(ctx) }
        #expect(requests.urls.allSatisfy { !$0.path.contains("/apps/") })
    }
}

/// Collects request URLs from a `@Sendable` mock handler.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
    var urls: [URL] { lock.withLock { storage } }
}
