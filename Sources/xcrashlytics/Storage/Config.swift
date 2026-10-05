//
//  Config.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// One Firebase app configuration inside a project-local profile.
struct AppProfile: Codable, Sendable, Equatable {
    /// Firebase app id for this environment/platform.
    var appId: String
    /// App bundle id — scopes Xcode Organizer crash scanning to
    /// `~/Library/Developer/Xcode/Products/<bundleId>`.
    var bundleId: String?
    /// Optional path this profile was discovered from, such as
    /// `Staging/GoogleService-Info.plist` or `app/google-services.json`.
    var sourcePath: String?

    init(appId: String, bundleId: String? = nil, sourcePath: String? = nil) {
        self.appId = appId
        self.bundleId = bundleId
        self.sourcePath = sourcePath
    }
}

/// Project-local settings, persisted to `.xcrashlytics.json` at the repo root.
///
/// Deliberately tiny: it holds only what the tool can't derive or find on its
/// own. Crash directories are standard OS paths (auto-scanned), and the Firebase
/// project number is derived from `appId`.
struct Config: Codable, Sendable, Equatable {
    /// Firebase app id, any platform (e.g. `1:1234567890:ios:abcdef0123456789`
    /// or `1:1234567890:android:…`). Required for the Firebase commands; the
    /// project number is extracted from it.
    var appId: String?

    /// Currently selected named profile. When this points at a known profile,
    /// Firebase commands use that profile's `appId`.
    var activeProfile: String?

    /// Named Firebase app profiles for project environments such as debug,
    /// staging, prerelease, and release.
    var profiles: [String: AppProfile]

    /// The app id Firebase commands should use.
    var resolvedAppId: String? {
        if let activeProfile,
           let profile = profiles[activeProfile.lowercased()] {
            return profile.appId
        }
        return appId
    }

    /// The bundle id Xcode crash scanning should scope to, when configured.
    var resolvedBundleId: String? {
        guard let activeProfile else { return nil }
        return profiles[activeProfile.lowercased()]?.bundleId
    }

    init(
        appId: String? = nil,
        activeProfile: String? = nil,
        profiles: [String: AppProfile] = [:]
    ) {
        self.appId = appId
        self.activeProfile = activeProfile?.lowercased()
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { key, value in
            (key.lowercased(), value)
        })
    }
}
