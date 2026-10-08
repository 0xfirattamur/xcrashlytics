import Foundation

protocol SubprocessExecutor: Sendable {
    /// Throws only when the process cannot be spawned; a non-zero exit is a result.
    func execute(executable: String, arguments: [String], standardInput: String?) throws -> SubprocessResult
}
