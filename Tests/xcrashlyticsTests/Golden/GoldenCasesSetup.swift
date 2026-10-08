import Foundation

extension GoldenCases {
    static let open: [GoldenCase] = [
        .init("open-fb", ["open", fatal]),
        .init("open-fb-event", ["open", "\(fatal)/events/E2"]),
        .init("open-fb-event-missing", ["open", "\(fatal)/events/NOPE"]),
        .init("open-fb-no-location", ["open", "FB-I4"]),
        .init("open-fb-no-events", ["open", "FB-IEMPTY"]),
        .init("open-fb-nonfatal-file-missing", ["open", nonFatal]),
        .init("open-fb-ambiguous", ["open", fatal], world: GoldenWorld(sources: .ambiguous)),
        .init("open-fb-no-sources", ["open", fatal], world: GoldenWorld(sources: .none)),
        .init("open-fb-build-output-only", ["open", fatal], world: GoldenWorld(sources: .buildOutputOnly)),
        .init("open-fb-xed-missing", ["open", fatal], world: GoldenWorld(launcherExitCode: 127)),
        .init("open-fb-xed-fails", ["open", fatal], world: GoldenWorld(launcherExitCode: 1)),
        .init("open-fb-link", ["open", "FB-I1/events/E1"]),
        .init("open-xc", ["open", xcode, "--crash-directory", crashDir]),
        .init("open-xc-ips", ["open", xcodeIPS, "--crash-directory", crashDir]),
        .init("open-xc-raw-report", ["open", "XC-99999999-2222-3333-4444-555555555555", "--crash-directory", GoldenWorld.rawCrashDirectory]),
        .init("open-xc-organizer", ["open", xcode]),
        .init("open-xc-ambiguous", ["open", xcode, "--crash-directory", crashDir], world: GoldenWorld(sources: .ambiguousViewController)),
        .init("open-xc-no-sources", ["open", xcode, "--crash-directory", crashDir], world: GoldenWorld(sources: .none)),
        .init("open-xc-launcher-fails", ["open", xcode, "--crash-directory", crashDir], world: GoldenWorld(launcherExitCode: 1)),
        .init("open-xc-unknown", ["open", "XC-NOPE", "--crash-directory", crashDir]),
        .init("open-xc-mixed", ["open", xcode, "--crash-directory", GoldenWorld.mixedCrashDirectory]),
        .init("open-xc-no-bundle", ["open", xcode], world: GoldenWorld(config: .noBundleId)),
        .init("open-bad-prefix", ["open", "ZZ-1"]),
    ]

    static let setup: [GoldenCase] = .flatten([initCases, useCases])

    private static let initCases: [GoldenCase] = [
        .init("init-scan", ["init", "--scan"], world: GoldenWorld(config: .missing, repoFiles: true)),
        .init("init-scan-existing", ["init", "--scan"], world: GoldenWorld(repoFiles: true)),
        .init("init-scan-widget-active", ["init", "--scan"], world: GoldenWorld(config: .widgetActive, repoFiles: true)),
        .init("init-scan-broken-plist", ["init", "--scan"], world: GoldenWorld(config: .missing, repoFiles: true, brokenPlist: true)),
        .init("init-scan-library", ["init", "--scan", "--app-library", "ExtraKit"], world: GoldenWorld(config: .missing, repoFiles: true)),
        .init("init-scan-nothing-found", ["init", "--scan"], world: .noConfig),
        .init("init-scan-invalid-config", ["init", "--scan"], world: GoldenWorld(config: .invalidFile, repoFiles: true)),
        .init("init-scan-firebase-missing", ["init", "--scan"], world: GoldenWorld(config: .missing, firebaseCLIInstalled: false, repoFiles: true)),
        .init("init-scan-with-manual-flags", ["init", "--scan", "--app-id", GoldenWorld.appId]),
        .init("init-manual", ["init", "--app-id", GoldenWorld.appId, "--profile", "release", "--bundle-id", "com.example.app"], world: .noConfig),
        .init("init-manual-no-organizer-crashes", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release", "--bundle-id", "com.example.other",
        ], world: .noConfig),
        .init("init-manual-no-bundle", ["init", "--app-id", GoldenWorld.appId, "--profile", "release"], world: .noConfig),
        .init("init-manual-library", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "Release", "--app-library", "KeyboardKit", "--app-library", "Imaging",
        ], world: .noConfig),
        .init("init-manual-existing-profile", ["init", "--app-id", GoldenWorld.widgetAppId, "--profile", "app", "--bundle-id", "com.example.app"]),
        .init("init-manual-keeps-libraries", ["init", "--app-id", GoldenWorld.appId, "--profile", "app"]),
        .init("init-manual-bad-app-id", ["init", "--app-id", "not-an-app-id", "--profile", "release"], world: .noConfig),
        .init("init-manual-firebase-missing", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release",
        ], world: GoldenWorld(config: .missing, firebaseCLIInstalled: false)),
        .init("init-manual-login-missing", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release",
        ], world: GoldenWorld(config: .missing, login: .missing)),
        .init("init-manual-login-missing-no-cli", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release",
        ], world: GoldenWorld(config: .missing, login: .missing, firebaseCLIInstalled: false)),
        .init("init-manual-login-revoked", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release",
        ], world: GoldenWorld(config: .missing, login: .revoked)),
        .init("init-manual-token-service-down", [
            "init", "--app-id", GoldenWorld.appId, "--profile", "release",
        ], world: GoldenWorld(config: .missing, login: .tokenServiceDown)),
        .init("init-manual-invalid-config", ["init", "--app-id", GoldenWorld.appId, "--profile", "release"], world: GoldenWorld(config: .invalidFile)),
        .init("init-no-flags", ["init"]),
        .init("init-only-app-id", ["init", "--app-id", GoldenWorld.appId]),
        .init("init-empty-app-id", ["init", "--app-id", " ", "--profile", "release"]),
        .init("init-empty-library", ["init", "--app-id", GoldenWorld.appId, "--profile", "release", "--app-library", " "]),
    ]

    private static let useCases: [GoldenCase] = [
        .init("use-widget", ["use", "widget"]),
        .init("use-app", ["use", "app"]),
        .init("use-uppercase", ["use", "WIDGET"]),
        .init("use-unknown", ["use", "staging"]),
        .init("use-empty", ["use", " "]),
        .init("use-no-config", ["use", "app"], world: .noConfig),
        .init("use-invalid-config", ["use", "app"], world: GoldenWorld(config: .invalidFile)),
        .init("use-legacy-app-id-only", ["use", "app"], world: .noConfigAppId),
        .init("use-missing-argument", ["use"]),
    ]
}
