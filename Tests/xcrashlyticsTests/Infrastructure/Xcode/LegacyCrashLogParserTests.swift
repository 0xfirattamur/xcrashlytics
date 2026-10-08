import Foundation
import Testing
@testable import xcrashlytics

@Suite("LegacyCrashLogParser")
struct LegacyCrashLogParserTests {
    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses legacy .crash into CrashEvent")
    func parsesLegacy() throws {
        let text = try loadFixture("sample.crash")
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let event = try parser.parse(text: text, path: "sample.crash").event
        #expect(event.source == .xcode)
        #expect(event.bundleId == "com.example.ExampleApp")
        #expect(event.exception.exceptionType == "EXC_BAD_ACCESS")
        #expect(event.exception.signal == "SIGSEGV")
        #expect(event.binaryImages.count == 2)
        #expect(event.frames.count == 3)
        #expect(event.frames[0].binaryName == "ExampleApp")
        #expect(event.frames[0].symbol == "-[ExampleViewController crashNow]")
        #expect(event.frames[0].isSymbolicated == true)
    }

    @Test("symbolicated frames carry the trailing (File.swift:line) source location")
    func parsesSourceLocations() throws {
        let text = try loadFixture("sample-symbolicated.crash")
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let event = try parser.parse(text: text, path: "sample-symbolicated.crash").event
        #expect(event.frames[0].file == "ExampleViewController.swift")
        #expect(event.frames[0].line == 42)
        #expect(event.frames[0].symbol == "-[ExampleViewController crashNow]")
        // Apple writes "(:-1)" when there is no source info — stays nil.
        #expect(event.frames[2].file == nil)
        #expect(event.frames[2].line == nil)
        #expect(event.frames[2].symbol == "UIApplicationMain")
    }

    @Test("parses a real Organizer .crash end to end")
    func parsesRealOrganizerCrash() throws {
        let text = try loadFixture("organizer-real.crash")
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let event = try parser.parse(text: text, path: "organizer-real.crash").event
        #expect(event.source == .xcode)
        #expect(event.bundleId == "com.codeway.cleanerplus")
        #expect(event.id == "XC-A75A8BDD-967C-4AFE-B361-3782A0E8B296")
        #expect(event.providerId == "A75A8BDD-967C-4AFE-B361-3782A0E8B296")
        #expect(event.exception.exceptionType == "EXC_CRASH")
        #expect(event.exception.signal == "SIGABRT")
        #expect(event.deviceModel == "iPhone16,2")
        #expect(event.crashedThreadIndex == 41)
        #expect(!event.binaryImages.isEmpty)
        // Frames come from the crashed-thread section even at a high thread index; Thread 0's first frame is mach_msg2_trap.
        #expect(event.frames[0].index == 0)
        #expect(event.frames[0].symbol == "__pthread_kill")
        #expect(event.frames[0].binaryName == "libsystem_kernel.dylib")
        // Organizer Date/Time carries 4 fractional digits.
        let timestamp = try #require(event.timestamp)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timestamp)
        #expect([c.year, c.month, c.day, c.hour, c.minute, c.second] == [2026, 5, 20, 14, 54, 30])
    }

    @Test("frame and image lines with spaced binary names parse")
    func parsesSpacedBinaryNames() throws {
        let text = """
    Incident Identifier: 11111111-2222-3333-4444-555555555555
    Identifier:          com.example.myapp
    Exception Type:      EXC_CRASH (SIGABRT)
    Triggered by Thread: 0

    Thread 0 Crashed:
    0   My App                        \t0x0000000102f74a68 main + 64 (main.swift:23)

    Binary Images:
    0x102f70000 - 0x102f7ffff My App arm64  <11223344556677881122334455667788> /var/containers/My App.app/My App
    """
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let event = try parser.parse(text: text, path: "spaced.crash").event
        #expect(event.frames.count == 1)
        #expect(event.frames[0].binaryName == "My App")
        #expect(event.frames[0].symbol == "main")
        #expect(event.frames[0].file == "main.swift")
        #expect(event.frames[0].line == 23)
        #expect(event.binaryImages.count == 1)
        #expect(event.binaryImages[0].name == "My App")
        #expect(event.binaryImages[0].arch == "arm64")
        #expect(event.binaryImages[0].path == "/var/containers/My App.app/My App")
        #expect(event.frames[0].imageUUID == event.binaryImages[0].uuid)
    }

    @Test("symbol drops the source location when the frame has no + offset")
    func symbolWithoutOffsetDropsLocation() throws {
        let text = """
    Incident Identifier: 11111111-2222-3333-4444-555555555555
    Identifier:          com.example.myapp
    Exception Type:      EXC_CRASH (SIGABRT)
    Triggered by Thread: 0

    Thread 0 Crashed:
    0   MyApp    \t0x0000000102f74a68 main (main.swift:12)
    1   MyApp    \t0x0000000102f74b00 mach_msg2_trap (:-1)
    2   MyApp    \t0x0000000102f74c00 AppDelegate.application(_:didFinishLaunchingWithOptions:) + 540 (AppDelegate.swift:20)
    """
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let event = try parser.parse(text: text, path: "nooffset.crash").event
        #expect(event.frames[0].symbol == "main")
        #expect(event.frames[0].file == "main.swift")
        #expect(event.frames[0].line == 12)
        // "(:-1)" marker: stripped from the symbol, yields no source info.
        #expect(event.frames[1].symbol == "mach_msg2_trap")
        #expect(event.frames[1].file == nil)
        #expect(event.frames[1].line == nil)
        // Swift signature parens are NOT a location — symbol stays intact.
        #expect(event.frames[2].symbol == "AppDelegate.application(_:didFinishLaunchingWithOptions:)")
        #expect(event.frames[2].file == "AppDelegate.swift")
        #expect(event.frames[2].line == 20)
    }

    @Test("id falls back to a stable content hash when Incident Identifier is missing")
    func stableIdFallback() throws {
        let text = """
    Identifier:          com.example.myapp
    Exception Type:      EXC_CRASH (SIGABRT)
    Triggered by Thread: 0

    Thread 0 Crashed:
    0   MyApp    \t0x0000000102f74a68 main + 64 (main.swift:23)
    """
        let parser = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        let first = try parser.parse(text: text, path: "noid.crash").event
        let second = try parser.parse(text: text, path: "noid.crash").event
        #expect(first.id == second.id)
        #expect(!first.id.isEmpty)
        let other = try parser.parse(text: text + "\n1   MyApp    \t0x0000000102f74b00 helper + 8 (:-1)", path: "noid.crash").event
        #expect(other.id != first.id)
    }
}
