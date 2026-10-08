import Foundation
@testable import xcrashlytics

/// Scripted `SubprocessExecutor` for tests.
///
/// Test sets up a closure that maps `(executable, arguments)` to a
/// `SubprocessResult`. Default behavior is to throw — forces every test path to
/// be explicit about what subprocess calls it expects.
final class StubSubprocessExecutor: SubprocessExecutor, @unchecked Sendable {
    /// `(executable, arguments) -> SubprocessResult` lookup. Return `nil` to
    /// fall back to the throw-on-miss default.
    var handler: ((String, [String]) -> SubprocessResult?)?
    /// History of every invocation — useful for asserting "was atos called".
    private(set) var calls: [(String, [String])] = []

    init(handler: ((String, [String]) -> SubprocessResult?)? = nil) {
        self.handler = handler
    }

    func execute(executable: String, arguments: [String], standardInput: String?) throws -> SubprocessResult {
        calls.append((executable, arguments))
        if let result = handler?(executable, arguments) {
            return result
        }
        throw NSError(
            domain: "StubSubprocessExecutor",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no handler for \(executable) \(arguments)"]
        )
    }
}
