import Foundation

/// Where command output and diagnostics go. Production writes to the real
/// streams; tests can inject `RecordingConsole` to capture writes.
protocol CLIConsole: Sendable {
    /// Writes to stdout verbatim (no newline appended).
    func output(_ text: String)
    /// Writes "warning: <message>\n" to stderr.
    func warn(_ message: String)
    /// Writes "error: <message>\n" to stderr.
    func error(_ message: String)
}

struct StandardConsole: CLIConsole {
    func output(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }

    func error(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}

/// Test double that records everything written.
final class RecordingConsole: CLIConsole, @unchecked Sendable {
    private(set) var outputs: [String] = []
    private(set) var warnings: [String] = []
    private(set) var errors: [String] = []

    init() {}

    func output(_ text: String) { outputs.append(text) }
    func warn(_ message: String) { warnings.append(message) }
    func error(_ message: String) { errors.append(message) }
}
