extension CommandContext {
    /// Loads local Xcode crashes. Explicit `directories` are scanned as given;
    /// otherwise the active profile's Organizer directories are scanned, which
    /// requires a bundle id. Warnings are returned, not printed.
    func loadXcodeCrashes(directories: [String] = []) throws -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        guard directories.isEmpty else { return scan(directories) }
        let config = try ConfigFile(fileSystem: fileSystem).load()
        guard let bundleId = config.resolvedBundleId else {
            throw ConfigError.missingBundleId(profile: config.activeProfile)
        }
        return loadOrganizerCrashes(bundleId: bundleId)
    }

    /// Organizer crashes for `bundleId`. Xcode files app-extension reports
    /// under the containing app, so reports from a containing app's directory
    /// are kept only when their own bundle id matches.
    func loadOrganizerCrashes(bundleId: String) -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        let directories = XcodeCrashLoader.standardDirectories(bundleId: bundleId)
        let load = scan(directories)
        let ownDirectory = directories.first.map { $0 + "/" }
        let crashes = load.crashes.filter { crash in
            ownDirectory.map(crash.filePath.hasPrefix) == true
                || crash.event.bundleId?.caseInsensitiveCompare(bundleId) == .orderedSame
        }
        return (crashes, load.warnings)
    }

    private func scan(_ directories: [String]) -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        let result = XcodeCrashLoader(fs: fileSystem).load(directories: directories)
        return (result.crashes, result.warnings.map(CLIWarning.init))
    }
}
