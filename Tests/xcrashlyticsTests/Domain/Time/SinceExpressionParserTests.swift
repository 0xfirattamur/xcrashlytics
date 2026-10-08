import Foundation
import Testing
@testable import xcrashlytics

@Suite("since duration")
struct SinceExpressionParserTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("parses d/h/m suffixes")
    func parses() throws {
        #expect(try SinceExpressionParser.cutoffDate(from: "7d", now: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(try SinceExpressionParser.cutoffDate(from: "24h", now: now) == now.addingTimeInterval(-24 * 3_600))
        #expect(try SinceExpressionParser.cutoffDate(from: "30m", now: now) == now.addingTimeInterval(-30 * 60))
    }

    @Test("all and none mean no cutoff")
    func allMeansNil() throws {
        #expect(try SinceExpressionParser.cutoffDate(from: "all", now: now) == nil)
        #expect(try SinceExpressionParser.cutoffDate(from: "none", now: now) == nil)
    }

    @Test("garbage throws SinceExpressionError")
    func garbageThrows() {
        #expect(throws: SinceExpressionError.invalid("7x")) {
            _ = try SinceExpressionParser.cutoffDate(from: "7x", now: now)
        }
    }

    @Test("parses weeks, decimals, case and surrounding space")
    func parsesExtendedForms() throws {
        #expect(try SinceExpressionParser.cutoffDate(from: "2w", now: now) == now.addingTimeInterval(-14 * 86_400))
        #expect(try SinceExpressionParser.cutoffDate(from: "1.5d", now: now) == now.addingTimeInterval(-129_600))
        #expect(try SinceExpressionParser.cutoffDate(from: " 12H ", now: now) == now.addingTimeInterval(-12 * 3_600))
        #expect(try SinceExpressionParser.cutoffDate(from: "ALL", now: now) == nil)
    }

    @Test("rejects zero, negative, signed, hex, exponent, non-finite and malformed amounts")
    func rejectsLenientForms() {
        let bad = [
            "0d", "0.0h", "-5d", "+7d", "0x10d", "1e3m", "infd", "nand", "1e400d", "7", "d", "", "7s", "7dd",
            "7 d", "1..5d", ".5d", "5.d", "99999999999999999999999999999999999999999999999999999999999999999"
                + "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
                + "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
                + "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
                + "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
                + "9999999999999999999999999999999999999999999999999999999999999999999999999999999999d",
        ]
        for value in bad {
            #expect(throws: SinceExpressionError.invalid(value), "\(value.prefix(12))") {
                _ = try SinceExpressionParser.cutoffDate(from: value, now: now)
            }
        }
    }
}
