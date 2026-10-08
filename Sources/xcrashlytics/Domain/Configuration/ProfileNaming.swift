import Foundation

enum ProfileNaming {
    /// Keeps the name of an existing profile with the same app id, so a re-scan never
    /// renames the user's profiles; `extensionOf` follows the renaming.
    static func resolvingNames(_ discovery: AppDiscoveryResult, existing: Config) -> AppDiscoveryResult {
        var result = discovery
        var finalNames: [String: String] = [:]
        for app in discovery.apps {
            let known = existing.profiles.filter { $0.value.appId == app.appId }
            let match = known.first { $0.value.sourcePath == app.sourcePath }?.key ?? known.keys.sorted().first
            finalNames[app.profileName] = match ?? app.profileName
        }
        result.apps = discovery.apps.map { app in
            var copy = app
            copy.profileName = finalNames[app.profileName] ?? app.profileName
            copy.extensionOf = app.extensionOf.map { finalNames[$0] ?? $0 }
            return copy
        }
        return result
    }

    static func mergedLibraries(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        return lists.flatMap { $0 }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
