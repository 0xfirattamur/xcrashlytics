import Foundation
@testable import xcrashlytics

/// `DateProvider` test double — returns the same `Date` until tests advance it.
final class FixedDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ initial: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.current = initial
    }

    func currentDate() -> Date { lock.withLock { current } }

    /// Advances the clock by `seconds`.
    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
