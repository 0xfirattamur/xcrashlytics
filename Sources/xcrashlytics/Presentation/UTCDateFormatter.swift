import Foundation

enum UTCDateFormatter {
    static let minuteFormat = "yyyy-MM-dd HH:mm 'UTC'"
    static let dayFormat = "yyyy-MM-dd"

    static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
