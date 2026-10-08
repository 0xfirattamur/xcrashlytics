import Foundation
import Testing
@testable import xcrashlytics

@Suite("LegacyCrashLogParser robustness")
struct LegacyCrashLogParserRobustnessTests {
    private let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())

    @Test("a thread NAME containing 'Crashed' does not hijack the crashed-thread section")
    func threadNameCollision() throws {
        let parsed = try parser.parse(text: XcodeFixtures.text("crashed-thread-name-collision.crash"), path: "c.crash")
        #expect(parsed.event.crashedThreadIndex == 1)
        #expect(parsed.event.frames.map(\.symbol) == ["crashingFunction"])
        #expect(parsed.warnings.isEmpty)
    }

    @Test("CRLF files parse like LF: clean ids, bundle id, frames stop at the blank line")
    func crlf() throws {
        let lf = try XcodeFixtures.text("sample-symbolicated.crash")
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let event = try parser.parse(text: crlf, path: "crlf.crash").event
        #expect(event.id == "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(event.bundleId == "com.example.ExampleApp")
        #expect(event.frames.count == 3)
        #expect(event.binaryImages.count == 2)
        #expect(event.binaryImages.allSatisfy { !$0.path.contains("\r") })
        #expect(event == (try parser.parse(text: lf, path: "crlf.crash").event))
    }

    @Test("Triggered by Thread selects its section even when another section is marked Crashed")
    func triggeredHeaderWins() throws {
        let text = """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 2

        Thread 1 Crashed:
        0   App    0x0000000100001000 wrong + 4

        Thread 2:
        0   App    0x0000000100002000 right + 4
        """
        let event = try parser.parse(text: text, path: "t.crash").event
        #expect(event.crashedThreadIndex == 2)
        #expect(event.frames.map(\.symbol) == ["right"])
    }

    @Test("legacy 'Crashed Thread:' header selects the thread")
    func legacyCrashedThreadHeader() throws {
        let text = """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_BAD_ACCESS (SIGSEGV)
        Crashed Thread:      3

        Thread 3:
        0   App    0x0000000100002000 culprit + 4
        """
        let parsed = try parser.parse(text: text, path: "old.crash")
        #expect(parsed.event.crashedThreadIndex == 3)
        #expect(parsed.event.frames.map(\.symbol) == ["culprit"])
        #expect(parsed.warnings.isEmpty)
    }

    @Test("a report with no crashed-thread section warns instead of silently having no frames")
    func missingCrashedSection() throws {
        let text = """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 5

        Thread 0:
        0   App    0x0000000100002000 other + 4
        """
        let parsed = try parser.parse(text: text, path: "x.crash")
        #expect(parsed.event.frames.isEmpty)
        let warning = try #require(parsed.warnings.first)
        #expect(warning.code == "XCODE_NO_THREAD_FRAMES")
        #expect(warning.path == "x.crash")
    }

    @Test("legacy image names ('+MyApp (1.0)') link frames to their image")
    func legacyImageNames() throws {
        let text = """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 0

        Thread 0 Crashed:
        0   MyApp    0x0000000102f74a68 main + 64

        Binary Images:
        0x102f70000 - 0x102f7ffff +MyApp (1.0) arm64  <11223344556677881122334455667788> /var/containers/MyApp.app/MyApp
        """
        let event = try parser.parse(text: text, path: "legacy.crash").event
        #expect(event.binaryImages.map(\.name) == ["MyApp"])
        #expect(event.frames[0].imageUUID == "11223344-5566-7788-1122-334455667788")
    }

    @Test("non-UTF-8 bytes in a name do not fail the whole report")
    func lossyUTF8() throws {
        let fileStore = InMemoryFileStore()
        var data = Data(try XcodeFixtures.text("sample.crash").utf8)
        data.append(contentsOf: [0x0A, 0xFF, 0xFE, 0x0A])
        fileStore.seed("/lossy.crash", data: data)
        let event = try CrashReportParserRegistry(fileStore: fileStore).parse(path: "/lossy.crash").event
        #expect(event.id == "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(event.frames.count == 3)
    }

    @Test("an incident identifier that is not a single token falls back to a stable hash id")
    func incidentIdSanitized() throws {
        let text = """
        Incident Identifier: not a valid id!
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 0

        Thread 0 Crashed:
        0   App    0x0000000100002000 f + 4
        """
        let event = try parser.parse(text: text, path: "bad-id.crash").event
        #expect(!event.id.contains(" "))
        #expect(event.id.count == "XC-".count + 32)
        #expect(try parser.parse(text: text, path: "bad-id.crash").event.id == event.id)
    }

    @Test("frames with a hex constant inside the symbol are still symbolicated; address-only ones are not")
    func isSymbolicatedIsWholeToken() throws {
        let text = """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 0

        Thread 0 Crashed:
        0   App    0x0000000100002000 closure #1 in Foo.bar(flag: 0x1) + 4
        1   App    0x0000000100002100 0x100000000 + 8448
        """
        let frames = try parser.parse(text: text, path: "hex.crash").event.frames
        #expect(frames[0].isSymbolicated)
        #expect(!frames[1].isSymbolicated)
    }

    @Test("unsymbolicated fixture: frames are marked unsymbolicated")
    func unsymbolicatedFrames() throws {
        let event = try parser.parse(text: XcodeFixtures.text("unsymbolicated.crash"), path: "u.crash").event
        #expect(event.frames.map(\.isSymbolicated) == [true, false, false, true])
    }

    @Test("a text report that is a diagnostic event, not a crash, is unsupported — not malformed")
    func diagnosticTextReport() {
        let text = "Event:   hang\nIncident Identifier: 1\nDuration: 3s\n"
        #expect(throws: CrashReportParseError.self) { try parser.parse(text: text, path: "hang.crash") }
        do {
            _ = try parser.parse(text: text, path: "hang.crash")
        } catch let error as CrashReportParseError {
            guard case .unsupportedReport = error else {
                Issue.record("expected unsupportedReport, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
