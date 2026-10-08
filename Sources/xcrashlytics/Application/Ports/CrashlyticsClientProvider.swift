/// Builds Crashlytics clients for the apps the config knows.
protocol CrashlyticsClientProvider: Sendable {
    /// The client for the active profile's app. Throws `ConfigError.missingAppId` when there is none.
    func client() throws -> CrashlyticsClient
    /// The client for the profile whose bundle id matches a pasted console link.
    func client(for link: FirebaseConsoleLink) throws -> CrashlyticsClient
}
