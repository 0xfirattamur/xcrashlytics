import Foundation

extension GoldenCases {
    static let failures: [GoldenCase] = .flatten([configFailures, authFailures, apiFailures, inputFailures, parseFailures, faultFailures])

    private static let configFailures: [GoldenCase] = .flatten([
        .formats("err-config-missing-issues", ["issues"], world: .noConfig),
        .formats("err-config-missing-events", ["events", fatal], ["text", "json"], world: .noConfig),
        .formats("err-config-invalid-issues", ["issues"], world: GoldenWorld(config: .invalidFile)),
        .formats("err-bad-app-id-issues", ["issues"], world: GoldenWorld(config: .badAppId)),
        [
            .init("err-config-missing-show-json", ["show", fatal, "--format", "json"], world: .noConfig),
            .init("err-config-missing-export-json", ["export", fatal, "--format", "json"], world: .noConfig),
            .init("err-config-missing-export-md", ["export", fatal], world: .noConfig),
            .init("err-config-missing-blame-json", ["blame", "--format", "json"], world: .noConfig),
            .init("err-config-missing-groups-json", ["groups", "--format", "json"], world: .noConfig),
            .init("err-config-missing-breakdown-json", ["breakdown", "--by", "os", "--format", "json"], world: .noConfig),
            .init("err-config-missing-open-text", ["open", fatal], world: .noConfig),
            .init("err-config-invalid-show-json", ["show", fatal, "--format", "json"], world: GoldenWorld(config: .invalidFile)),
            .init("err-config-invalid-xcode-json", ["issues", "--xcode", "--format", "json"], world: GoldenWorld(config: .invalidFile)),
            .init("err-no-bundle-xcode-json", ["issues", "--xcode", "--format", "json"], world: GoldenWorld(config: .noBundleId)),
            .init("err-no-bundle-xcode-text", ["issues", "--xcode"], world: GoldenWorld(config: .noBundleId)),
            .init("err-no-bundle-groups-json", ["groups", "--xcode", "--format", "json"], world: GoldenWorld(config: .noBundleId)),
            .init("err-no-config-xcode-json", ["issues", "--xcode", "--format", "json"], world: .noConfig),
            .init("err-bad-app-id-events-json", ["events", fatal, "--format", "json"], world: GoldenWorld(config: .badAppId)),
            .init("err-bad-app-id-breakdown-text", ["breakdown", "--by", "version"], world: GoldenWorld(config: .badAppId)),
        ],
    ])

    private static let authFailures: [GoldenCase] = .flatten([
        .formats("err-auth-required-issues", ["issues"], world: GoldenWorld(login: .missing)),
        .formats("err-auth-expired-issues", ["issues"], world: GoldenWorld(login: .revoked)),
        [
            .init("err-auth-required-events-json", ["events", fatal, "--format", "json"], world: GoldenWorld(login: .missing)),
            .init("err-auth-required-show-text", ["show", fatal], world: GoldenWorld(login: .missing)),
            .init("err-auth-required-export-json", ["export", fatal, "--format", "json"], world: GoldenWorld(login: .missing)),
            .init("err-auth-required-breakdown-json", ["breakdown", "--by", "os", "--format", "json"], world: GoldenWorld(login: .missing)),
            .init("err-auth-expired-blame-json", ["blame", "--format", "json"], world: GoldenWorld(login: .revoked)),
            .init("err-token-service-issues-json", ["issues", "--format", "json"], world: GoldenWorld(login: .tokenServiceDown)),
            .init("err-token-service-issues-text", ["issues"], world: GoldenWorld(login: .tokenServiceDown)),
            .init("err-unauthorized-events-json", ["events", "FB-I401", "--format", "json"]),
            .init("err-unauthorized-events-text", ["events", "FB-I401"]),
            .init("err-permission-denied-events-json", ["events", "FB-I403", "--format", "json"]),
            .init("err-permission-denied-events-text", ["events", "FB-I403"]),
            .init("err-permission-denied-show-json", ["show", "FB-I403", "--format", "json"]),
        ],
    ])

    private static let apiFailures: [GoldenCase] = .flatten([
        .formats("err-not-found-events", ["events", "FB-I404"]),
        .formats("err-rate-limited-events", ["events", "FB-I429"]),
        .formats("err-api-error-events", ["events", "FB-I500"]),
        [
            .init("err-not-found-show-json", ["show", "FB-I404", "--format", "json"]),
            .init("err-not-found-show-text", ["show", "FB-I404"]),
            .init("err-not-found-export-json", ["export", "FB-I404", "--format", "json"]),
            .init("err-not-found-export-md", ["export", "FB-I404"]),
            .init("err-not-found-open-text", ["open", "FB-I404"]),
            .init("err-not-found-breakdown-json", ["breakdown", "FB-I404", "--by", "version", "--format", "json"]),
            .init("err-not-found-groups-json", ["groups", "FB-I404", "--format", "json"]),
            .init("err-rate-limited-show-json", ["show", "FB-I429", "--format", "json"]),
            .init("err-rate-limited-breakdown-json", ["breakdown", "FB-I429", "--by", "version", "--format", "json"]),
            .init("err-rate-limited-export-text", ["export", "FB-I429"]),
            .init("err-api-error-show-text", ["show", "FB-I500"]),
            .init("err-api-error-export-json", ["export", "FB-I500", "--format", "json"]),
            .init("err-decoding-events-json", ["events", "FB-IBAD", "--format", "json"]),
            .init("err-decoding-events-text", ["events", "FB-IBAD"]),
            .init("err-network-events-json", ["events", "FB-INET", "--format", "json"]),
            .init("err-network-events-text", ["events", "FB-INET"]),
            .init("err-report-failing-issues-json", ["issues", "--format", "json"], world: GoldenWorld(failingReports: ["topIssues"])),
            .init("err-report-failing-issues-text", ["issues"], world: GoldenWorld(failingReports: ["topIssues"])),
            .init("err-report-failing-breakdown-json", [
                "breakdown", "--by", "device", "--format", "json",
            ], world: GoldenWorld(failingReports: ["topAppleDevices"])),
        ],
    ])

    private static let inputFailures: [GoldenCase] = .flatten([
        .formats("err-limit-zero-issues", ["issues", "--limit", "0"]),
        .formats("err-since-too-long-issues", ["issues", "--since", "91d"]),
        .formats("err-since-nonsense-issues", ["issues", "--since", "soon"]),
        [
            .init("err-search-limit-zero-json", ["issues", "--search-limit", "0", "--format", "json"]),
            .init("err-events-per-issue-zero-json", ["issues", "--events-per-issue", "0", "--format", "json"]),
            .init("err-min-events-negative-json", ["issues", "--min-events", "-1", "--format", "json"]),
            .init("err-min-events-negative-text", ["issues", "--min-events", "-1"]),
            .init("err-empty-query-json", ["issues", " ", "--format", "json"]),
            .init("err-empty-match-json", ["issues", "--match", " ", "--format", "json"]),
            .init("err-empty-user-id-json", ["issues", "--user-id", " ", "--format", "json"]),
            .init("err-app-version-invalid-json", ["issues", "--app-version", "latest", "--format", "json"]),
            .init("err-since-version-invalid-text", ["issues", "--since-version", "x.y"]),
            .init("err-events-no-issue-json", ["events", "--format", "json"]),
            .init("err-events-no-issue-text", ["events"]),
            .init("err-events-latest-and-limit-json", ["events", fatal, "--latest", "--limit", "2", "--format", "json"]),
            .init("err-events-latest-and-limit-text", ["events", fatal, "--latest", "--limit", "2"]),
            .init("err-events-limit-zero-json", ["events", fatal, "--limit", "0", "--format", "json"]),
            .init("err-events-bad-id-json", ["events", "ZZ-1", "--format", "json"]),
            .init("err-events-bad-id-text", ["events", "not an id"]),
            .init("err-events-since-too-long-json", ["events", fatal, "--since", "120d", "--format", "json"]),
            .init("err-show-bad-id-text", ["show", "nonsense"]),
            .init("err-export-bad-id-json", ["export", "nonsense", "--format", "json"]),
            .init("err-export-since-too-long-json", ["export", fatal, "--since", "120d", "--format", "json"]),
            .init("err-export-since-nonsense-md", ["export", fatal, "--since", "soon"]),
            .init("err-blame-top-zero-text", ["blame", "--top", "0"]),
            .init("err-blame-issue-limit-zero-json", ["blame", "--issue-limit", "0", "--format", "json"]),
            .init("err-blame-concurrency-zero-json", ["blame", "--concurrency", "0", "--format", "json"]),
            .init("err-breakdown-limit-zero-json", ["breakdown", "--by", "os", "--limit", "0", "--format", "json"]),
            .init("err-breakdown-since-too-long-text", ["breakdown", "--by", "os", "--since", "120d"]),
            .init("err-groups-bad-id-json", ["groups", "nonsense", "--format", "json"]),
        ],
    ])

    private static let faultFailures: [GoldenCase] = .flatten([
        .formats("err-internal-config-unreadable", ["issues"], world: GoldenWorld(fileFault: .unreadableConfig)),
        [
            .init("err-internal-config-unreadable-show-json", ["show", fatal, "--format", "json"], world: GoldenWorld(fileFault: .unreadableConfig)),
            .init("err-internal-config-unreadable-use-text", ["use", "app"], world: GoldenWorld(fileFault: .unreadableConfig)),
            .init("err-internal-read-only-use-text", ["use", "widget"], world: GoldenWorld(fileFault: .readOnly)),
            .init("err-internal-read-only-init-text", [
                "init", "--app-id", GoldenWorld.appId, "--profile", "release",
            ], world: GoldenWorld(config: .missing, fileFault: .readOnly)),
            .init("err-internal-read-only-export-output-json", [
                "export", fatal, "--format", "json", "--output", "/tmp/golden/crash.json",
            ], world: GoldenWorld(fileFault: .readOnly)),
            .init("issues-crash-dir-unscannable-json", [
                "issues", "--crash-directory", crashDir, "--format", "json",
            ], world: GoldenWorld(fileFault: .unscannableCrashDirectory)),
            .init("issues-crash-dir-unscannable-text", [
                "issues", "--crash-directory", crashDir,
            ], world: GoldenWorld(fileFault: .unscannableCrashDirectory)),
            .init("show-xc-unscannable-text", [
                "show", xcode, "--crash-directory", crashDir,
            ], world: GoldenWorld(fileFault: .unscannableCrashDirectory)),
        ],
    ])

    private static let parseFailures: [GoldenCase] = [
        .init("err-unknown-flag-text", ["issues", "--bogus"]),
        .init("err-unknown-flag-json", ["issues", "--bogus", "--format", "json"]),
        .init("err-unknown-flag-ndjson", ["events", fatal, "--bogus", "--format", "ndjson"]),
        .init("err-missing-value-json", ["issues", "--limit", "--format", "json"]),
        .init("err-missing-value-ndjson", ["issues", "--format=ndjson", "--limit"]),
        .init("err-missing-value-text", ["issues", "--limit"]),
        .init("err-bad-number-json", ["issues", "--format", "json", "--limit", "abc"]),
        .init("err-bad-number-text", ["issues", "--limit", "abc"]),
        .init("err-bad-format-text", ["issues", "--format", "yaml"]),
        .init("err-bad-format-after-json", ["issues", "--format", "json", "--format", "yaml"]),
        .init("err-unexpected-argument-json", ["issues", "one", "two", "--format", "json"]),
        .init("err-missing-argument-show-json", ["show", "--format", "json"]),
        .init("err-missing-argument-show-text", ["show"]),
        .init("err-missing-argument-open-text", ["open"]),
        .init("err-missing-argument-export-json", ["export", "--format=json"]),
        .init("err-show-ndjson-flag-after-ids-json", ["show", fatal, "--bogus", "--format=json"]),
        .init("err-double-dash-text", ["issues", "--", "--format", "json", "--bogus"]),
        .init("err-subcommand-bogus-json", ["bogus", "--format", "json"]),
        .init("err-init-unknown-flag-text", ["init", "--bogus"]),
        .init("err-use-extra-argument-text", ["use", "app", "extra"]),
    ]
}
