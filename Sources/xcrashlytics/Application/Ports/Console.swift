import Foundation

/// Where command output and diagnostics go.
protocol Console: Sendable {
    func writeOutput(_ text: String)
    /// Writes `warning: <message>` and a newline to stderr.
    func reportWarning(_ message: String)
    func writeDiagnostic(_ text: String)
}
