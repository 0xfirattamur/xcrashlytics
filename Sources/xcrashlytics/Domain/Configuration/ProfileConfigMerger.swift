import Foundation

enum ProfileConfigMerger {
    /// A scan never guesses among several apps: it keeps a still-valid active profile,
    /// activates a lone discovery, and otherwise leaves it unset.
    static func merging(
        scan discovery: AppDiscoveryResult, libraries extra: [String], into existing: Config
    ) -> Config {
        var config = existing
        for app in discovery.apps {
            let previous = config.profiles[app.profileName]
            let libraries = ProfileNaming.mergedLibraries(
                previous?.appLibraries ?? [], discovery.appLibraries, extra)
            config.profiles[app.profileName] = AppProfile(
                appId: app.appId,
                bundleId: app.bundleId ?? previous?.bundleId,
                sourcePath: app.sourcePath,
                appLibraries: libraries,
                extensionOf: app.extensionOf ?? previous?.extensionOf)
        }
        if !hasValidActiveProfile(config) {
            config.activeProfile = discovery.apps.count == 1 ? discovery.apps[0].profileName : nil
        }
        return config
    }

    private static func hasValidActiveProfile(_ config: Config) -> Bool {
        guard let active = config.activeProfile else { return false }
        return config.profiles[active] != nil
    }

    static func merging(
        appId: String, profile name: String, bundleId: String?, libraries: [String], into existing: Config
    ) -> Config {
        var config = existing
        let old = config.profiles[name]
        config.profiles[name] = AppProfile(
            appId: appId,
            bundleId: bundleId ?? old?.bundleId,
            sourcePath: old?.appId == appId ? old?.sourcePath : nil,
            appLibraries: libraries.isEmpty ? old?.appLibraries : ProfileNaming.mergedLibraries(libraries),
            extensionOf: old?.extensionOf)
        config.activeProfile = name
        return config
    }
}
