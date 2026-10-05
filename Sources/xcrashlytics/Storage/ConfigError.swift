import Foundation

/// Errors raised while resolving the project config.
enum ConfigError: Error, Equatable, Sendable {
    /// No appId resolvable — `init` or `use` has not been run in this project.
    case missingAppId
    /// Active profile has no bundle id — Xcode crash commands cannot scope
    /// their scan to `~/Library/Developer/Xcode/Products/<bundleId>`.
    case missingBundleId(profile: String?)
    /// Project config exists but is not valid JSON.
    case invalidFile
}
