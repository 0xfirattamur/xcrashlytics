import Foundation

enum FirebaseAppId {
    static func projectNumber(from appId: String) -> String? {
        let parts = appId.split(separator: ":")
        guard parts.count >= 4, let number = UInt64(parts[1]) else { return nil }
        return String(number)
    }
}
