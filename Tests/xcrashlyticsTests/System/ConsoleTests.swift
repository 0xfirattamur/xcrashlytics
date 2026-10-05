import Testing
@testable import xcrashlytics

@Suite("console")
struct ConsoleTests {
    @Test("recording console captures output, warnings, and errors")
    func recording() {
        let console = RecordingConsole()
        console.output("payload\n")
        console.warn("careful")
        console.error("broken")
        #expect(console.outputs == ["payload\n"])
        #expect(console.warnings == ["careful"])
        #expect(console.errors == ["broken"])
    }
}
