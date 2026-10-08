struct CrashSourceLoader: Sendable {
    let clients: CrashlyticsClientProvider
    let configRepository: ConfigRepository
    let xcodeCrashRepository: XcodeCrashRepository

    /// With `optional`, an unconfigured Firebase app yields `nil`; any other failure still throws.
    func firebaseClient(optional: Bool) throws -> CrashlyticsClient? {
        do {
            return try clients.client()
        } catch ConfigError.missingAppId where optional {
            return nil
        }
    }

    /// Without explicit `directories`, loads the active profile's Organizer crashes, which needs a bundle id.
    func xcodeCrashes(directories: [String]) throws -> XcodeCrashLoadResult {
        guard directories.isEmpty else { return xcodeCrashRepository.crashes(in: directories) }
        let config = try configRepository.load()
        guard let bundleId = config.resolvedBundleId else {
            throw ConfigError.missingBundleId(profile: config.activeProfile)
        }
        return xcodeCrashRepository.organizerCrashes(bundleId: bundleId)
    }
}
