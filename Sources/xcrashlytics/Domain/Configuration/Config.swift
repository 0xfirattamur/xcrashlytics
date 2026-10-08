import Foundation

struct Config: Codable, Sendable, Equatable {
    var appId: String?
    var activeProfile: String?
    var profiles: [String: AppProfile]

    var resolvedAppId: String? {
        if let activeProfile,
           let profile = profiles[activeProfile.lowercased()] {
            return profile.appId
        }
        return appId
    }

    var resolvedBundleId: String? {
        guard let activeProfile else { return nil }
        return profiles[activeProfile.lowercased()]?.bundleId
    }

    var resolvedAppLibraries: Set<String> {
        guard let activeProfile else { return [] }
        return Set((profiles[activeProfile.lowercased()]?.appLibraries ?? []).map { $0.lowercased() })
    }

    init(
        appId: String? = nil,
        activeProfile: String? = nil,
        profiles: [String: AppProfile] = [:]
    ) {
        self.appId = appId
        self.activeProfile = activeProfile?.lowercased()
        self.profiles = Dictionary(
            profiles.sorted { $0.key < $1.key }.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, later in later })
    }

    // Profile names are lowercased like in `init`, so a hand-edited `"Release"` key stays
    // reachable; keys that differ only by case are ambiguous and invalidate the file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawProfiles = try container.decodeIfPresent([String: AppProfile].self, forKey: .profiles) ?? [:]
        let names = rawProfiles.keys.map { $0.lowercased() }
        guard Set(names).count == names.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles, in: container,
                debugDescription: "profile names must be unique ignoring case")
        }
        self.init(
            appId: try container.decodeIfPresent(String.self, forKey: .appId),
            activeProfile: try container.decodeIfPresent(String.self, forKey: .activeProfile),
            profiles: rawProfiles)
    }
}
