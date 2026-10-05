import ArgumentParser
import Testing
@testable import xcrashlytics

@Suite("output format")
struct OutputFormatTests {
    @Test("parses the three formats")
    func parses() {
        #expect(OutputFormat(argument: "text") == .text)
        #expect(OutputFormat(argument: "json") == .json)
        #expect(OutputFormat(argument: "ndjson") == .ndjson)
        #expect(OutputFormat(argument: "yaml") == nil)
    }

    @Test("isJSON is false only for text")
    func isJSON() {
        #expect(!OutputFormat.text.isJSON)
        #expect(OutputFormat.json.isJSON)
        #expect(OutputFormat.ndjson.isJSON)
    }

    @Test("events accepts ndjson")
    func eventsAcceptsNDJSON() throws {
        _ = try EventsCommand.parse(["FB-a", "--format", "ndjson"])
    }

    @Test("blame accepts ndjson")
    func blameAcceptsNDJSON() throws {
        _ = try BlameCommand.parse(["--format", "ndjson"])
    }
}
