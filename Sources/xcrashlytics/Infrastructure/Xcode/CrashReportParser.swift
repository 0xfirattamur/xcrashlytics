import Foundation

/// Each parser recognises its format from the content, not the file extension.
protocol CrashReportParser: Sendable {
    func canParse(_ text: String) -> Bool
    func parse(text: String, path: String) throws -> ParsedCrashReport
}
