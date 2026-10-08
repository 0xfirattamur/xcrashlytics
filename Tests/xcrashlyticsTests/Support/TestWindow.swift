import Foundation

/// A fixed 90-day window for tests that only need some interval to pass.
enum TestWindow {
    static let end = Date(timeIntervalSince1970: 1_700_000_000)
    static let interval = DateInterval(start: end.addingTimeInterval(-90 * 86_400), end: end)
    /// Its RFC 3339 `filter.interval.*` query values.
    static let startQuery = "2023-08-16T22:13:20Z"
    static let endQuery = "2023-11-14T22:13:20Z"
}
