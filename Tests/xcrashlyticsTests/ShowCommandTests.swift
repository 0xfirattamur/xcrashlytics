//
//  ShowCommandTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore
import XCrashlyticsTestSupport
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
        let fs = InMemoryFileSystem()
        let configJSON = #"{"activeProfile":"dev","profiles":{"dev":"#
            + #"{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        fs.seed("\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json", text: configJSON)
        let crashDir = XcodeCrashLoader.standardDirectories(bundleId: "com.example.app")[0]
        fs.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))

        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: SystemClock()
        )

        let cmd = try ShowCommand.parse([
            "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        ])
        let out = try await cmd.runWithContext(ctx)

        #expect(out.contains("Exception: EXC_BAD_ACCESS"))
        #expect(out.contains("-[ExampleViewController crashNow]"))
    }

    @Test("rejects unknown id prefix")
    func rejectsBadId() async throws {
        let ctx = CommandContext(
            fileSystem: InMemoryFileSystem(),
            processRunner: MockProcessRunner(),
            clock: SystemClock()
        )
        let cmd = try ShowCommand.parse(["BOGUS-abc"])
        await #expect(throws: (any Error).self) {
            _ = try await cmd.runWithContext(ctx)
        }
    }

    @Test("FB issue detail includes latest event frames")
    func firebaseShowIncludesLatestEventFrames() async throws {
        let fs = try makeConfig()
        let http = MockHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
            return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{
              "eventId":"E1",
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]
            }]}
            """#.utf8))
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try ShowCommand.parse(["FB-I1", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
        )

        let data = try Envelope(output).data
        #expect(data["id"]?.string == "FB-I1")
        #expect(data["providerId"]?.string == "I1")
        #expect(data["frames"]?[0]?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
        #expect(data["frames"]?[0]?["file"]?.string == "BlurDetectionService.swift")
    }

    @Test("FB issue show renders a sampled summary header")
    func firebaseShowRendersSummaryHeader() async throws {
        let fs = try makeConfig()
        let http = MockHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","firstSeenVersion":"6.2.0","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E1","eventTime":"2026-06-10T08:00:00Z",
               "device":{"model":"iPhone 17 Pro Max"},
               "operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"u1"},
               "threads":[{"crashed":true,"frames":[{"symbol":"doWork()","library":"Core"}]}]},
              {"eventId":"E2","eventTime":"2026-06-01T08:00:00Z",
               "device":{"model":"iPhone 16"},
               "operatingSystem":{"displayVersion":"26.4.1"},
               "user":{"id":"u2"}}
            ]}
            """#.utf8))
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try ShowCommand.parse(["FB-I1"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
        )

        #expect(output.contains("Sampled:   newest 2 events, 2026-06-01 → 2026-06-10, 2 users"))
        #expect(output.contains("OS:        iOS 26.4.1 ×2"))
        #expect(output.contains("Devices:   iPhone 16 ×1, iPhone 17 Pro Max ×1"))
        #expect(output.contains("doWork()"))
    }

    @Test("FB issue show can filter latest event frames to app frames")
    func firebaseShowFiltersAppFrames() async throws {
        let fs = try makeConfig()
        let http = MockHTTPClient { request in
            if request.url?.path.hasSuffix("/issues/I1") == true {
                return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
                {"id":"I1","title":"Blur crash","errorType":"EXC_BAD_ACCESS","subtitle":"SIGSEGV","lastSeenVersion":"6.16.0"}
                """#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/events") == true)
            return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
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
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try ShowCommand.parse(["FB-I1", "--app-frames-only", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
        )

        let frames = try #require(Envelope(output).data["frames"]?.array)
        #expect(frames.count == 1)
        #expect(frames.first?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
        #expect(!frames.contains { $0["binaryName"]?.string == "libsystem_kernel.dylib" })
    }

    @Test("FB event id shows that event's frames")
    func firebaseEventShowIncludesFrames() async throws {
        let fs = try makeConfig()
        let http = MockHTTPClient { request in
            #expect(request.url?.path.hasSuffix("/events") == true)
            #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
            return MockHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{
              "eventId":"E1",
              "eventTime":"2026-06-05T12:09:45Z",
              "version":{"displayVersion":"6.16.0","buildVersion":"937"},
              "device":{"model":"iPhone 17 Pro Max"},
              "threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]
            }]}
            """#.utf8))
        }
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try ShowCommand.parse(["FB-I1/events/E1", "--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)
        )

        let data = try Envelope(output).data
        #expect(data["id"]?.string == "FB-I1/events/E1")
        #expect(data["deviceModel"]?.string == "iPhone 17 Pro Max")
        #expect(data["frames"]?[0]?["symbol"]?.string == "BlurDetectionService.classifyWithML(_:)")
    }

    private func makeConfig() throws -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        return fs
    }
}
