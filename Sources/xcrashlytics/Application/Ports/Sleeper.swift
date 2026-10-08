import Foundation

protocol Sleeper: Sendable {
    /// Throws `CancellationError` when the calling task is cancelled.
    func sleep(seconds: Double) async throws
}
