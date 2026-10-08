import Foundation

struct AppProfile: Codable, Sendable, Equatable {
    var appId: String
    /// App bundle id — scopes Xcode Organizer crash scanning to
    /// `~/Library/Developer/Xcode/Products/<bundleId>`.
    var bundleId: String?
    /// File the profile was discovered from, e.g. `Staging/GoogleService-Info.plist`.
    var sourcePath: String?
    /// Crashlytics quirk: labels first-party frameworks `THIRD_PARTY`; listing them here
    /// makes their frames count as app frames.
    var appLibraries: [String]?
    var extensionOf: String?

    init(
        appId: String, bundleId: String? = nil, sourcePath: String? = nil,
        appLibraries: [String]? = nil, extensionOf: String? = nil
    ) {
        self.appId = appId
        self.bundleId = bundleId
        self.sourcePath = sourcePath
        self.appLibraries = appLibraries?.isEmpty == true ? nil : appLibraries
        self.extensionOf = extensionOf
    }
}
