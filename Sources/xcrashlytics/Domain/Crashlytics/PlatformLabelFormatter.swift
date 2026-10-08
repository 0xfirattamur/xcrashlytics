import Foundation

enum PlatformLabelFormatter {
    static func os(_ version: String, platform: String?) -> String {
        guard let name = name(for: platform) else { return version }
        return "\(name) \(version)"
    }

    private static func name(for platform: String?) -> String? {
        guard let platform = platform?.trimmedNonEmpty else { return nil }
        switch platform.uppercased() {
        case "IOS": return "iOS"
        case "ANDROID": return "Android"
        case "IPADOS": return "iPadOS"
        case "MACOS": return "macOS"
        case "TVOS": return "tvOS"
        case "WATCHOS": return "watchOS"
        default: return platform.capitalized
        }
    }
}
