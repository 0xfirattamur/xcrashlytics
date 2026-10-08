import Foundation
import Testing
@testable import xcrashlytics

@Suite("payload encoder")
struct JSONPayloadEncoderTests {
    struct Sample: Encodable {
        var b = "two"
        var a = "one"
        var when = Date(timeIntervalSince1970: 0)
        var url = "https://example.com/x"
        var note = "line1\nline2"
    }

    @Test("json uses iso8601 dates, unescaped slashes, trailing newline")
    func json() throws {
        let output = try JSONPayloadEncoder().json(Sample())
        let decoded = try JSON.parse(output)
        #expect(decoded["a"]?.string == "one")
        #expect(decoded["when"]?.string == "1970-01-01T00:00:00Z")
        #expect(decoded["url"]?.string == "https://example.com/x")
        #expect(output.contains("https://example.com/x"))
        #expect(output.hasSuffix("\n"))
    }

    @Test("ndjson line is a single line with no trailing newline")
    func ndjsonLine() throws {
        let output = try JSONPayloadEncoder().ndjsonLine(Sample())
        #expect(!output.contains("\n"))
        let decoded = try JSON.parse(output)
        #expect(decoded["a"]?.string == "one")
        #expect(decoded["when"]?.string == "1970-01-01T00:00:00Z")
        #expect(decoded["note"]?.string == "line1\nline2")
    }
}
