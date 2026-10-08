protocol XcodeCrashRepository: Sendable {
    /// Crashes under exactly these directories; none is filtered by bundle id.
    func crashes(in directories: [String]) -> XcodeCrashLoadResult
    /// Organizer crashes belonging to `bundleId`, including its app extensions' reports.
    func organizerCrashes(bundleId: String) -> XcodeCrashLoadResult
}
