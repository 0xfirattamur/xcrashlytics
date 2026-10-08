import Foundation

struct ProfileSetupService: Sendable {
    let configRepository: ConfigRepository
    let appDiscovery: AppDiscovery
    let loginProbe: FirebaseLoginProbe
    let xcodeCrashes: XcodeCrashRepository
    let workingDirectory: String

    // MARK: - Public API

    func setup(_ request: InitRequest) async throws -> InitResult {
        // An existing config that cannot be read must stop init, never be overwritten.
        let existing = try configRepository.load()
        let discovery = try discoverApps(for: request, existing: existing)
        let checks = try await verify(request, discovery: discovery)
        let libraries = mergedLibraries(for: request, discovery: discovery)

        guard !checks.contains(where: \.blocks) else {
            return InitResult(discovered: discovery.apps, libraries: libraries, checks: checks, outcome: .blocked)
        }
        let updated = mergedConfig(for: request, discovery: discovery, into: existing)
        try configRepository.save(updated)
        return InitResult(
            discovered: discovery.apps,
            libraries: libraries,
            checks: checks,
            outcome: .written(activeProfile: updated.activeProfile))
    }

    // MARK: - Discovery and merging

    private func discoverApps(for request: InitRequest, existing: Config) throws -> AppDiscoveryResult {
        guard request.mode == .scan else { return .empty }
        let discovered = try appDiscovery.discover(from: workingDirectory)
        return ProfileNaming.resolvingNames(discovered, existing: existing)
    }

    private func mergedLibraries(for request: InitRequest, discovery: AppDiscoveryResult) -> [String] {
        guard request.mode == .scan else { return [] }
        return ProfileNaming.mergedLibraries(discovery.appLibraries, request.appLibraries)
    }

    private func mergedConfig(
        for request: InitRequest, discovery: AppDiscoveryResult, into existing: Config
    ) -> Config {
        switch request.mode {
        case .scan:
            return ProfileConfigMerger.merging(scan: discovery, libraries: request.appLibraries, into: existing)
        case let .manual(appId, profile):
            return ProfileConfigMerger.merging(
                appId: appId,
                profile: profile,
                bundleId: request.bundleId,
                libraries: request.appLibraries,
                into: existing)
        }
    }

    // MARK: - Environment checks

    private func verify(_ request: InitRequest, discovery: AppDiscoveryResult) async throws -> [SetupCheck] {
        let cliCheck = checkFirebaseCLI()
        let loginCheck = await checkFirebaseLogin(isFirebaseCLIInstalled: cliCheck.passed)
        let environmentChecks = [cliCheck, loginCheck]
        switch request.mode {
        case let .manual(appId, _):
            return environmentChecks + [Self.checkAppId(appId), checkBundleId(request.bundleId)]
        case .scan:
            return environmentChecks + scanChecks(for: discovery)
        }
    }

    private func scanChecks(for discovery: AppDiscoveryResult) -> [SetupCheck] {
        let unreadable = discovery.unreadable.map {
            SetupCheck.warn("\($0) is unreadable or not a valid Firebase config file — skipped.")
        }
        guard !discovery.apps.isEmpty else {
            let nothingFound = SetupCheck.fail(
                "no GoogleService-Info.plist or google-services.json found under \(workingDirectory).",
                hint: ["Run from the repo root, or: xcrashlytics init --app-id <APP_ID> --profile <name>"])
            return unreadable + [nothingFound]
        }
        let missingBundleId = discovery.apps.filter { $0.bundleId == nil }.map {
            SetupCheck.warn("\($0.profileName): no bundle id in \($0.sourcePath) — Xcode crash commands need one.")
        }
        return unreadable + missingBundleId
    }

    private func checkFirebaseCLI() -> SetupCheck {
        guard loginProbe.isCLIInstalled() else {
            return .fail(
                "firebase CLI is not installed. Install it, then run `firebase login`:",
                hint: [
                    "npm install -g firebase-tools   # or: brew install firebase-cli",
                    "firebase login",
                ])
        }
        return .ok
    }

    private func checkFirebaseLogin(isFirebaseCLIInstalled: Bool) async -> SetupCheck {
        guard loginProbe.hasStoredLogin() else {
            return isFirebaseCLIInstalled ? .fail("firebase login not completed. Run: firebase login") : .ok
        }
        do {
            try await loginProbe.verifyAccessToken()
            return .ok
        } catch {
            return Self.loginCheck(forTokenError: error)
        }
    }

    /// Only a rejected refresh token blocks; transport failures warn because the config can still be
    /// written offline.
    static func loginCheck(forTokenError error: Error) -> SetupCheck {
        switch error {
        case AccessTokenError.refreshTokenInvalid:
            return .fail("firebase refresh token is invalid. Run: firebase login --reauth")
        case let AccessTokenError.tokenExchangeFailed(reason):
            return .warn("firebase token exchange failed: \(reason)")
        case AccessTokenError.firebaseLoginRequired:
            return .fail("firebase login required. Run: firebase login")
        case let CrashlyticsClientError.network(reason):
            return .warn("could not reach Google to verify the firebase login (\(reason)).")
        default:
            return .warn("could not verify the firebase login: \(error.localizedDescription)")
        }
    }

    private static func checkAppId(_ appId: String) -> SetupCheck {
        guard FirebaseAppId.projectNumber(from: appId) != nil else {
            return .fail("appId=\(appId) has wrong format. Expected '1:<number>:<platform>:<hash>'.")
        }
        return .ok
    }

    private func checkBundleId(_ bundleId: String?) -> SetupCheck {
        guard let bundleId else {
            return .warn("no bundle id — Xcode crash commands need one. Re-run with --bundle-id <BUNDLE_ID>.")
        }
        guard !xcodeCrashes.organizerCrashes(bundleId: bundleId).crashes.isEmpty else {
            return .warn("no Organizer crashes for \(bundleId) yet — open Xcode Organizer once to download.")
        }
        return .ok
    }
}
