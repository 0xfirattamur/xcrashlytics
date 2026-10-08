import Foundation
import Testing
@testable import xcrashlytics

@Suite("IPS crash parser")
struct IPSCrashParserTests {
    private let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())

    @Test("parses a JSON .ips crash into the same CrashEvent shape as a .crash")
    func parsesIPS() throws {
        let parsed = try parser.parse(text: XcodeFixtures.text("ips-crash.ips"), path: "x.ips")
        let event = parsed.event
        #expect(parsed.warnings.isEmpty)
        #expect(event.id == "XC-0A0A0A0A-1111-2222-3333-444444444444")
        #expect(event.providerId == "0A0A0A0A-1111-2222-3333-444444444444")
        #expect(event.source == .xcode)
        #expect(event.bundleId == "com.example.ExampleApp")
        #expect(event.bundleVersion == "1.0 (42)")
        #expect(event.osVersion == "iOS 17.0 (21A329)")
        #expect(event.deviceModel == "iPhone14,2")
        #expect(event.exception.exceptionType == "EXC_BAD_ACCESS")
        #expect(event.exception.signal == "SIGSEGV")
        #expect(event.exception.subtype == "KERN_INVALID_ADDRESS at 0x0000000000000000")
        #expect(event.rawPath == "x.ips")
        let timestamp = try #require(event.timestamp)
        let reference = try #require(ISO8601DateFormatter().date(from: "2026-05-01T12:34:55Z"))
        #expect(abs(timestamp.timeIntervalSince(reference) - 0.1234) < 0.01)
    }

    @Test("frames come from the triggered thread, with image names, addresses, uuids and source locations")
    func triggeredThreadFrames() throws {
        let event = try parser.parse(text: XcodeFixtures.text("ips-crash.ips"), path: "x.ips").event
        #expect(event.crashedThreadIndex == 1)
        #expect(event.frames.map(\.symbol) == ["__pthread_kill", "ExampleViewController.crashNow()", nil, "UIApplicationMain"])
        #expect(event.frames.map(\.binaryName) == ["libsystem_kernel.dylib", "ExampleApp", "ExampleApp", "UIKitCore"])
        let crash = event.frames[1]
        #expect(crash.file == "ExampleViewController.swift")
        #expect(crash.line == 42)
        #expect(crash.address == 4_294_967_296 + 4096)
        #expect(crash.imageUUID == "11111111-1111-1111-1111-111111111111")
        #expect(crash.isSymbolicated)
        #expect(!event.frames[2].isSymbolicated)
        #expect(event.binaryImages.count == 3)
        #expect(event.binaryImages[0].uuid == "11111111-1111-1111-1111-111111111111")
        #expect(event.binaryImages[0].path.hasSuffix("ExampleApp.app/ExampleApp"))
        #expect(event.binaryImages[0].loadAddress == 4_294_967_296)
    }

    @Test("the .ips culprit is the app frame, and the unsymbolicated app frame drives the dSYM hint")
    func signatureAndHint() throws {
        let event = try parser.parse(text: XcodeFixtures.text("ips-crash.ips"), path: "x.ips").event
        let signature = try #require(CrashSignature.of(event))
        #expect(signature.symbol == "exampleviewcontroller.crashnow()")
        #expect(signature.module == "ExampleApp")
        let crash = XcodeCrash(event: event, filePath: "x.ips", fileMtime: Date(), fileSize: 1)
        #expect(SymbolicationAdvisor.hint(for: [crash]) == "1 app dSYM UUID(s) may be needed for 1 Xcode crash(es).")
    }

    @Test("a non-crash .ips (jetsam/hang/diagnostic) is unsupported with a clear reason")
    func nonCrashIPS() throws {
        let text = try XcodeFixtures.text("ips-hang.ips")
        do {
            _ = try parser.parse(text: text, path: "h.ips")
            Issue.record("expected unsupportedReport")
        } catch let error as CrashReportParseError {
            guard case .unsupportedReport(let message) = error else {
                Issue.record("expected unsupportedReport, got \(error)")
                return
            }
            #expect(message.contains("bug_type 298"))
        }
    }

    @Test("a truncated .ips is a malformed body with a clean message")
    func corruptIPS() throws {
        let text = try XcodeFixtures.text("ips-corrupt.ips")
        do {
            _ = try parser.parse(text: text, path: "c.ips")
            Issue.record("expected malformedBody")
        } catch let error as CrashReportParseError {
            #expect(error == .malformedBody("the .ips body after the header line is not valid JSON"))
        }
    }

    @Test("a triggered-less .ips falls back to faultingThread; none at all warns")
    func faultingThreadFallback() throws {
        var text = try XcodeFixtures.text("ips-crash.ips")
        text = text.replacingOccurrences(of: "\"triggered\" : true,", with: "")
        let fallback = try parser.parse(text: text, path: "f.ips")
        #expect(fallback.event.crashedThreadIndex == 1)
        #expect(fallback.event.frames.count == 4)

        let none = text.replacingOccurrences(of: "\"faultingThread\" : 1,", with: "")
        let parsed = try parser.parse(text: none, path: "n.ips")
        #expect(parsed.event.frames.isEmpty)
        #expect(parsed.warnings.map(\.code) == ["XCODE_NO_THREAD_FRAMES"])
    }
}
