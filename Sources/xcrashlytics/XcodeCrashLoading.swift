//
//  XcodeCrashLoading.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import XCrashlyticsCore

extension CommandContext {
    /// Loads local Xcode crashes from the given directories. Warnings are
    /// returned, not printed: the command decides where they go.
    func loadXcodeCrashes(directories: [String]) -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        let result = XcodeCrashLoader(fs: fileSystem).load(directories: directories)
        return (result.crashes, result.warnings.map(CLIWarning.init))
    }

    /// Organizer crash directories, scoped to the configured bundle id.
    /// Throws when no bundle id is resolvable from the config — Xcode crash
    /// commands refuse to run an unscoped scan.
    func xcodeCrashDirectories() throws -> [String] {
        let config = try ConfigFile(fileSystem: fileSystem).load()
        guard let bundleId = config.resolvedBundleId else {
            throw ConfigError.missingBundleId(profile: config.activeProfile)
        }
        return XcodeCrashLoader.standardDirectories(bundleId: bundleId)
    }
}
