import Foundation
@testable import xcrashlytics

/// `Sleeper` test double — records delays without actually sleeping.
final class SpySleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []

    init() {}

    var delays: [Double] { lock.withLock { recorded } }

    func sleep(seconds: Double) async throws {
        lock.withLock { recorded.append(seconds) }
    }
}
