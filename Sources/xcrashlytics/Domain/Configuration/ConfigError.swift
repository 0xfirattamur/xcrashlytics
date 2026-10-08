import Foundation

enum ConfigError: Error, Equatable, Sendable {
    case missingAppId
    case missingBundleId(profile: String?)
    case invalidFile
    case invalidAppId(String)
}
