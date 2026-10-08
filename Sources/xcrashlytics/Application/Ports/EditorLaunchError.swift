import Foundation

/// `xed` or `open` exited non-zero.
struct EditorLaunchError: Error, LocalizedError, Equatable {
    var tool: String
    var exitCode: Int32
    var stderr: String?

    var errorDescription: String? {
        let stderrSuffix = stderr.map { ": \($0)" } ?? ""
        let hint = exitCode == 127 && tool == "xed" ? " (install Xcode, or run: xcode-select --install)" : ""
        return "\(tool) exited with status \(exitCode)\(stderrSuffix)\(hint)"
    }
}
