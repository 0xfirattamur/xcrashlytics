import Foundation

struct ReportWindow: Equatable, Sendable {
    // Crashlytics quirk: report intervals reach back at most 90 days.
    static let maxDays = 90
    static let defaultSince = "7d"

    let interval: DateInterval

    /// `since` nil means the last 7 days; `all`/`none` the maximum window.
    init(since: String?, now: Date) throws {
        let value = since ?? Self.defaultSince
        guard let start = try SinceExpressionParser.cutoffDate(from: value, now: now) else {
            self = .maximum(now: now)
            return
        }
        guard start < now, now.timeIntervalSince(start) <= Self.maximumSeconds else {
            throw InvalidInputError(
                "--since must be a window of at most \(Self.maxDays)d (the Crashlytics limit), "
                    + "e.g. 7d or 30d; got '\(value)'.")
        }
        interval = DateInterval(start: start, end: now)
    }

    private init(interval: DateInterval) {
        self.interval = interval
    }

    static func maximum(now: Date) -> ReportWindow {
        ReportWindow(interval: DateInterval(start: now.addingTimeInterval(-maximumSeconds), end: now))
    }

    private static let maximumSeconds = TimeInterval(maxDays) * 86_400
}
