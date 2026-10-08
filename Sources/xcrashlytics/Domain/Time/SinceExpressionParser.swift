import Foundation

/// Relative durations (`7d`, `24h`, `30m`, `2w`, `1.5d`) to a cutoff; `all`/`none` mean no cutoff.
/// The amount must be a plain positive decimal: no sign, hex, exponent, zero, or non-finite value.
enum SinceExpressionParser {
    static func cutoffDate(from value: String, now: Date) throws -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "all" || trimmed == "none" { return nil }
        guard let unit = trimmed.last, let unitSeconds = unitSeconds[unit] else {
            throw SinceExpressionError.invalid(value)
        }
        let digits = trimmed.dropLast()
        guard isPlainDecimal(digits), let amount = Double(digits), amount.isFinite, amount > 0 else {
            throw SinceExpressionError.invalid(value)
        }
        let seconds = amount * unitSeconds
        guard seconds.isFinite else { throw SinceExpressionError.invalid(value) }
        return now.addingTimeInterval(-seconds)
    }

    private static let unitSeconds: [Character: TimeInterval] = [
        "m": 60, "h": 3_600, "d": 86_400, "w": 604_800,
    ]

    private static func isPlainDecimal(_ text: Substring) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }
}
