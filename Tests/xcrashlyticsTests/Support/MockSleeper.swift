import Foundation
@testable import xcrashlytics

/// `Sleeper` test double — records delays without actually sleeping.
final class MockSleeper: Sleeper, @unchecked Sendable {
    private(set) var delays: [Double] = []

    init() {}

    func sleep(seconds: Double) async throws {
        delays.append(seconds)
    }
}
