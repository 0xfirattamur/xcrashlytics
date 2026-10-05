import Foundation
import Testing
@testable import xcrashlytics

@Suite("payload encoder")
struct PayloadEncoderTests {
    struct Sample: Encodable {
        var b = "two"
        var a = "one"
        var when = Date(timeIntervalSince1970: 0)
        var url = "https://example.com/x"
        var note = "line1\nline2"
    }

    @Test("json uses iso8601 dates, unescaped slashes, trailing newline")
    func json() throws {
        let out = try PayloadEncoder.json(Sample())
        let decoded = try JSON.parse(out)
        #expect(decoded["a"]?.string == "one")
        #expect(decoded["when"]?.string == "1970-01-01T00:00:00Z")
        #expect(decoded["url"]?.string == "https://example.com/x")
        #expect(out.contains("https://example.com/x"))
        #expect(out.hasSuffix("\n"))
    }

    @Test("ndjson line is a single line with no trailing newline")
    func ndjsonLine() throws {
        let out = try PayloadEncoder.ndjsonLine(Sample())
        #expect(!out.contains("\n"))
        let decoded = try JSON.parse(out)
        #expect(decoded["a"]?.string == "one")
        #expect(decoded["when"]?.string == "1970-01-01T00:00:00Z")
        #expect(decoded["note"]?.string == "line1\nline2")
    }
}
