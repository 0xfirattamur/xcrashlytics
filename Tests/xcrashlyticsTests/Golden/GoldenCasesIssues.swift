import Foundation

extension GoldenCases {
    static let issues: [GoldenCase] = .flatten([issuesFirebase, issuesFilters, issuesEventFilters, issuesXcode])

    private static let issuesFirebase: [GoldenCase] = .flatten([
        .formats("issues", ["issues"]),
        .formats("issues-query", ["issues", "blur"]),
        .formats("issues-query-nomatch", ["issues", "zzz-nothing"]),
        .formats("issues-limit-2", ["issues", "--limit", "2"]),
        .formats("issues-by-day", ["issues", "--by-day"]),
        .formats("issues-since-24h", ["issues", "--since", "24h"], ["text", "json"]),
        [
            .init("issues-since-30d-json", ["issues", "--since", "30d", "--format", "json"]),
            .init("issues-since-all-json", ["issues", "--since", "all", "--format", "json"]),
            .init("issues-since-2w-text", ["issues", "--since", "2w"]),
            .init("issues-search-limit-json", ["issues", "--search-limit", "3", "--format", "json"]),
            .init("issues-search-limit-capped-json", ["issues", "--search-limit", "5000", "--format", "json"]),
            .init("issues-search-limit-capped-text", ["issues", "--search-limit", "5000"]),
            .init("issues-search-truncated-json", ["issues", "zzz", "--search-limit", "5", "--format", "json"]),
            .init("issues-search-truncated-text", ["issues", "zzz", "--search-limit", "5"]),
            .init("issues-all-json", ["issues", "--all", "--format", "json"]),
            .init("issues-all-text", ["issues", "--all"]),
            .init("issues-widget-profile-json", ["issues", "--format", "json"], world: .widget),
            .init("issues-last-seen-unavailable-json", ["issues", "--format", "json"], world: GoldenWorld(failingEventIssues: ["I2"])),
            .init("issues-last-seen-unavailable-text", ["issues"], world: GoldenWorld(failingEventIssues: ["I2"])),
        ],
    ])

    private static let issuesFilters: [GoldenCase] = [
        .init("issues-app-version-json", ["issues", "--app-version", "6.16.0", "--format", "json"]),
        .init("issues-app-version-text", ["issues", "--app-version", "6.16.0"]),
        .init("issues-app-version-build-json", ["issues", "--app-version", "6.15.0 (900)", "--format", "json"]),
        .init("issues-app-version-by-day-json", ["issues", "--app-version", "6.16.0", "--by-day", "--format", "json"]),
        .init("issues-since-version-json", ["issues", "--since-version", "6.15.0", "--format", "json"]),
        .init("issues-since-version-ndjson", ["issues", "--since-version", "6.16.0", "--format", "ndjson"]),
        .init("issues-version-nomatch-json", ["issues", "--app-version", "9.9.9", "--format", "json"]),
        .init("issues-version-nomatch-text", ["issues", "--app-version", "9.9.9"]),
        .init("issues-version-nomatch-ndjson", ["issues", "--since-version", "9.9.9", "--format", "ndjson"]),
        .init("issues-type-fatal-json", ["issues", "--type", "FATAL", "--format", "json"]),
        .init("issues-type-nonfatal-text", ["issues", "--type", "NON_FATAL"]),
        .init("issues-type-lowercase-json", ["issues", "--type", "exc_bad_access", "--format", "json"]),
        .init("issues-min-events-json", ["issues", "--min-events", "10", "--format", "json"]),
        .init("issues-min-events-text", ["issues", "--min-events", "10"]),
        .init("issues-file-json", ["issues", "--file", "BlurService.swift", "--format", "json"]),
        .init("issues-symbol-json", ["issues", "--symbol", "objectdestroyTm", "--format", "json"]),
        .init("issues-match-json", ["issues", "--match", "maprenderer", "--format", "json"]),
        .init("issues-combined-json", [
            "issues", "blur", "--type", "FATAL", "--min-events", "2", "--since", "30d", "--limit", "1", "--by-day", "--format", "json",
        ]),
    ]

    private static let issuesEventFilters: [GoldenCase] = [
        .init("issues-user-id-json", ["issues", "--user-id", "user-secret-1", "--format", "json"]),
        .init("issues-user-id-text", ["issues", "--user-id", "user-secret-1"]),
        .init("issues-user-id-ndjson", ["issues", "--user-id", "user-secret-1", "--format", "ndjson"]),
        .init("issues-user-id-none-json", ["issues", "--user-id", "nobody", "--format", "json"]),
        .init("issues-user-id-truncated-json", ["issues", "--user-id", "user-other-2", "--events-per-issue", "1", "--format", "json"]),
        .init("issues-user-id-truncated-text", ["issues", "--user-id", "user-other-2", "--events-per-issue", "1"]),
        .init("issues-domain-json", ["issues", "--domain", "com.example.NetworkError", "--format", "json"]),
        .init("issues-domain-text", ["issues", "--domain", "com.example.NetworkError"]),
        .init("issues-domain-none-json", ["issues", "--domain", "com.nothing", "--format", "json"]),
        .init("issues-user-info-key-json", ["issues", "--user-info-key", "feature_flag=dark_mode", "--format", "json"]),
        .init("issues-user-info-key-text", ["issues", "--user-info-key", "retry"]),
        .init("issues-user-info-keys-json", ["issues", "--user-info-key", "userId", "--user-info-key", "retry=2", "--format", "json"]),
    ]

    private static let issuesXcode: [GoldenCase] = .flatten([
        .formats("issues-xcode", ["issues", "--xcode"]),
        .formats("issues-crash-dir", ["issues", "--crash-directory", crashDir]),
        [
            .init("issues-xcode-limit-json", ["issues", "--xcode", "--limit", "1", "--format", "json"]),
            .init("issues-xcode-query-json", ["issues", "ExampleViewController", "--xcode", "--format", "json"]),
            .init("issues-xcode-since-json", ["issues", "--xcode", "--since", "24h", "--format", "json"]),
            .init("issues-xcode-since-all-text", ["issues", "--xcode", "--since", "all"]),
            .init("issues-xcode-widget-json", ["issues", "--xcode", "--format", "json"], world: .widget),
            .init("issues-crash-dirs-json", ["issues", "--crash-directory", crashDir, "--crash-directory", GoldenWorld.rawCrashDirectory, "--format", "json"]),
            .init("issues-crash-dir-mixed-json", ["issues", "--crash-directory", GoldenWorld.mixedCrashDirectory, "--format", "json"]),
            .init("issues-crash-dir-mixed-text", ["issues", "--crash-directory", GoldenWorld.mixedCrashDirectory]),
            .init("issues-crash-dir-mixed-ndjson", ["issues", "--crash-directory", GoldenWorld.mixedCrashDirectory, "--format", "ndjson"]),
            .init("issues-crash-dir-noframes-json", ["issues", "--crash-directory", GoldenWorld.noFramesCrashDirectory, "--format", "json"]),
            .init("issues-crash-dir-missing-json", ["issues", "--crash-directory", "/nowhere", "--format", "json"]),
            .init("issues-xcode-user-id-json", ["issues", "--xcode", "--user-id", "user-secret-1", "--format", "json"]),
            .init("issues-xcode-skipped-json", ["issues", "--crash-directory", crashDir, "--format", "json"], world: .noConfig),
            .init("issues-xcode-skipped-text", ["issues", "--crash-directory", crashDir], world: .noConfig),
            .init("issues-xcode-skipped-ndjson", ["issues", "--crash-directory", crashDir, "--format", "ndjson"], world: .noConfig),
            .init("issues-xcode-hint-json", ["issues", "zzz", "--crash-directory", GoldenWorld.rawCrashDirectory, "--format", "json"]),
            .init("issues-xcode-hint-text", ["issues", "zzz", "--crash-directory", GoldenWorld.rawCrashDirectory]),
            .init("issues-xcode-hint-ndjson", ["issues", "zzz", "--crash-directory", GoldenWorld.rawCrashDirectory, "--format", "ndjson"]),
        ],
    ])
}
