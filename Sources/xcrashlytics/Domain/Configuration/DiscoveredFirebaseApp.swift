import Foundation

struct DiscoveredFirebaseApp: Sendable, Equatable {
    var profileName: String
    var appId: String
    var platform: String
    var bundleId: String?
    var sourcePath: String
    /// Profile name of the app this is an extension of (its bundle id is that app's plus a suffix).
    var extensionOf: String?

    init(
        profileName: String, appId: String, platform: String, bundleId: String? = nil, sourcePath: String,
        extensionOf: String? = nil
    ) {
        self.profileName = profileName
        self.appId = appId
        self.platform = platform
        self.bundleId = bundleId
        self.sourcePath = sourcePath
        self.extensionOf = extensionOf
    }
}
