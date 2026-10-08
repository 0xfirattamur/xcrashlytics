import Foundation
import Testing
@testable import xcrashlytics

@Suite("CrashReportParserRegistry")
struct CrashReportParserRegistryTests {
    @Test("an unreadable file is an ioError")
    func unreadableFile() {
        let registry = CrashReportParserRegistry(fileStore: InMemoryFileStore())
        #expect(throws: CrashReportParseError.self) { _ = try registry.parse(path: "/missing.crash") }
    }
}
