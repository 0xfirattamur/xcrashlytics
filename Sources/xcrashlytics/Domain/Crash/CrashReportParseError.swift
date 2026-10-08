import Foundation

/// Messages omit the file path: the loader attaches it to the warning it builds.
enum CrashReportParseError: Error, Equatable, Sendable, LocalizedError {
    case malformedHeader(String)
    case malformedBody(String)
    /// A well-formed report that is not a crash (hang, jetsam, diagnostics…).
    case unsupportedReport(String)
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .malformedHeader(let message), .malformedBody(let message),
             .unsupportedReport(let message), .ioError(let message):
            return message
        }
    }
}
