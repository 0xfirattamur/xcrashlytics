import Foundation

// Crashlytics quirk: timestamps are RFC 3339 with a time zone designator (offsets and fractional
// seconds allowed); anything else is unparseable and excluded by date filters. Day buckets are
// UTC days, so `23:30-05:00` falls on the next day.
enum EventTimestampParser {
    static func parse(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(value, strategy: Date.ISO8601FormatStyle())
    }

    static func dayString(from value: String?) -> String? {
        guard let value, let date = parse(value) else { return nil }
        return date.formatted(Date.ISO8601FormatStyle().year().month().day())
    }

    /// No cutoff admits everything; an unparseable timestamp is excluded.
    static func isIncluded(event: CrashlyticsEvent, onOrAfter cutoff: Date?) -> Bool {
        guard let cutoff else { return true }
        guard let eventTime = event.eventTime, let date = parse(eventTime) else { return false }
        return date >= cutoff
    }
}
