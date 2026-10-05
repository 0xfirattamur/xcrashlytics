import Foundation
@testable import xcrashlytics

/// `Clock` test double — returns the same `Date` until tests advance it.
final class FixedClock: Clock, @unchecked Sendable {
    private var current: Date

    init(_ initial: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.current = initial
    }

    func now() -> Date { current }

    /// Advances the clock by `seconds`.
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
