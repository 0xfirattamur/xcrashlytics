import Foundation

extension GoldenCases {
    static let groups: [GoldenCase] = .flatten([
        .formats("groups", ["groups"]),
        .formats("groups-issue", ["groups", fatal], ["text", "json"]),
        .formats("groups-xcode", ["groups", "--xcode"], ["text", "json"]),
        .formats("groups-crash-dir", ["groups", "--crash-directory", crashDir], ["text", "json"]),
        [
            .init("groups-firebase-limit-json", ["groups", "--firebase-limit", "3", "--format", "json"]),
            .init("groups-limit-1-json", ["groups", "--limit", "1", "--format", "json"]),
            .init("groups-limit-1-text", ["groups", "--limit", "1"]),
            .init("groups-since-30d-json", ["groups", "--since", "30d", "--format", "json"]),
            .init("groups-since-all-text", ["groups", "--since", "all"]),
            .init("groups-issue-not-in-window-json", ["groups", "FB-IDEEP", "--format", "json"]),
            .init("groups-issue-not-in-window-text", ["groups", "FB-IDEEP"]),
            .init("groups-issue-xcode-json", ["groups", fatal, "--xcode", "--format", "json"]),
            .init("groups-skipped-json", ["groups", "--crash-directory", crashDir, "--format", "json"], world: .noConfig),
            .init("groups-skipped-text", ["groups", "--crash-directory", crashDir], world: .noConfig),
            .init("groups-crash-dir-mixed-json", ["groups", "--crash-directory", GoldenWorld.mixedCrashDirectory, "--format", "json"]),
            .init("groups-crash-dir-mixed-text", ["groups", "--crash-directory", GoldenWorld.mixedCrashDirectory]),
            .init("groups-widget-profile-json", ["groups", "--format", "json"], world: .widget),
            .init("groups-firebase-limit-zero-json", ["groups", "--firebase-limit", "0", "--format", "json"]),
            .init("groups-limit-zero-text", ["groups", "--limit", "0"]),
        ],
    ])

    static let blame: [GoldenCase] = .flatten([
        .formats("blame", ["blame"]),
        .formats("blame-top-1", ["blame", "--top", "1"], ["text", "json"]),
        .formats("blame-issue-limit-2", ["blame", "--issue-limit", "2"], ["text", "json"]),
        .formats("blame-events-per-issue-2", ["blame", "--events-per-issue", "2"], ["text", "json"]),
        [
            .init("blame-since-30d-json", ["blame", "--since", "30d", "--format", "json"]),
            .init("blame-since-24h-text", ["blame", "--since", "24h"]),
            .init("blame-concurrency-1-json", ["blame", "--concurrency", "1", "--format", "json"]),
            .init("blame-widget-profile-json", ["blame", "--format", "json"], world: .widget),
            .init("blame-top-zero-json", ["blame", "--top", "0", "--format", "json"]),
            .init("blame-events-failing-json", ["blame", "--format", "json"], world: GoldenWorld(failingEventIssues: ["I2"])),
            .init("blame-events-failing-text", ["blame"], world: GoldenWorld(failingEventIssues: ["I2"])),
        ],
    ])

    static let breakdown: [GoldenCase] = .flatten([
        .formats("breakdown-version", ["breakdown", fatal, "--by", "version"]),
        .formats("breakdown-os", ["breakdown", fatal, "--by", "os"]),
        .formats("breakdown-device", ["breakdown", fatal, "--by", "device"]),
        .formats("breakdown-app-version", ["breakdown", "--by", "version"]),
        .formats("breakdown-app-os", ["breakdown", "--by", "os"]),
        .formats("breakdown-app-device", ["breakdown", "--by", "device"]),
        [
            .init("breakdown-limit-1-json", ["breakdown", fatal, "--by", "version", "--limit", "1", "--format", "json"]),
            .init("breakdown-limit-1-text", ["breakdown", "--by", "device", "--limit", "1"]),
            .init("breakdown-since-30d-json", ["breakdown", fatal, "--by", "os", "--since", "30d", "--format", "json"]),
            .init("breakdown-since-all-text", ["breakdown", fatal, "--by", "os", "--since", "all"]),
            .init("breakdown-event-id-json", ["breakdown", "\(fatal)/events/E2", "--by", "version", "--format", "json"]),
            .init("breakdown-link-json", ["breakdown", consoleLink, "--by", "device", "--format", "json"]),
            .init("breakdown-nonfatal-text", ["breakdown", nonFatal, "--by", "version"]),
            .init("breakdown-empty-json", ["breakdown", "FB-I3", "--by", "device", "--format", "json"]),
            .init("breakdown-widget-profile-json", ["breakdown", "--by", "version", "--format", "json"], world: .widget),
            .init("breakdown-report-failing-json", [
                "breakdown", "--by", "os", "--format", "json",
            ], world: GoldenWorld(failingReports: ["topOperatingSystems"])),
            .init("breakdown-missing-by-text", ["breakdown", fatal]),
            .init("breakdown-bad-by-text", ["breakdown", fatal, "--by", "color"]),
            .init("breakdown-missing-by-json", ["breakdown", fatal, "--format", "json"]),
            .init("breakdown-xc-id-json", ["breakdown", xcode, "--by", "version", "--format", "json"]),
        ],
    ])
}
