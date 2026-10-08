import Foundation

/// Organizer writes 4 fractional digits (`2026-05-20 15:54:30.5213 +0100`), `.ips` headers 2 or 3, some none.
enum CrashTimestamp {
    static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd HH:mm:ss.SSSS Z",
            "yyyy-MM-dd HH:mm:ss.SSS Z",
            "yyyy-MM-dd HH:mm:ss.SS Z",
            "yyyy-MM-dd HH:mm:ss.S Z",
            "yyyy-MM-dd HH:mm:ss Z"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
