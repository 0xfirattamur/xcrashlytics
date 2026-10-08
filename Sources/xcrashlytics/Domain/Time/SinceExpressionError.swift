import Foundation

enum SinceExpressionError: Error, Equatable, LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(value):
            "invalid --since '\(value)' — use a positive number with a unit of m, h, d or w "
                + "(for example 30m, 24h, 7d, 2w), or all."
        }
    }
}
