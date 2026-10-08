import Foundation

extension GoldenCases {
    static let show: [GoldenCase] = .flatten([showFirebase, showLinks, showXcode])

    private static let showFirebase: [GoldenCase] = .flatten([
        .formats("show", ["show", fatal], ["text", "json"]),
        .formats("show-event", ["show", "\(fatal)/events/E2"], ["text", "json"]),
        .formats("show-nonfatal", ["show", nonFatal], ["text", "json"]),
        .formats("show-no-crashed-thread", ["show", noCrashedThread], ["text", "json"]),
        .formats("show-i4", ["show", "FB-I4"], ["text", "json"]),
        .formats("show-app-frames-only", ["show", fatal, "--app-frames-only"], ["text", "json"]),
        .formats("show-no-system-frames", ["show", fatal, "--no-system-frames"], ["text", "json"]),
        .formats("show-crashing-thread-only", ["show", fatal, "--crashing-thread-only"], ["text", "json"]),
        .formats("show-breadcrumbs", ["show", fatal, "--breadcrumbs"], ["text", "json"]),
        .formats("show-dsym", ["show", fatal, "--dsym", GoldenWorld.dsymDirectory], ["text", "json"]),
        [
            .init("show-ndjson-unsupported", ["show", fatal, "--format", "ndjson"]),
            .init("show-nonfatal-crashing-thread-json", ["show", nonFatal, "--crashing-thread-only", "--format", "json"]),
            .init("show-nonfatal-crashing-thread-text", ["show", nonFatal, "--crashing-thread-only"]),
            .init("show-no-crashed-thread-crashing-json", ["show", noCrashedThread, "--crashing-thread-only", "--format", "json"]),
            .init("show-event-crashing-thread-json", ["show", "\(fatal)/events/E2", "--crashing-thread-only", "--format", "json"]),
            .init("show-nonfatal-app-frames-json", ["show", nonFatal, "--app-frames-only", "--format", "json"]),
            .init("show-dsym-atos-fails-json", [
                "show", fatal, "--dsym", GoldenWorld.dsymDirectory, "--format", "json",
            ], world: GoldenWorld(dsymTools: .atosFails)),
            .init("show-dsym-missing-text", ["show", fatal, "--dsym", "/empty-dsyms"]),
            .init("show-lowercase-id-json", ["show", "fb-I1", "--format", "json"]),
            .init("show-widget-profile-json", ["show", fatal, "--format", "json"], world: .widget),
            .init("show-version-report-unavailable-json", ["show", fatal, "--format", "json"], world: GoldenWorld(failingReports: ["topVersions"])),
            .init("show-version-report-unavailable-text", ["show", fatal], world: GoldenWorld(failingReports: ["topVersions"])),
            .init("show-events-empty-json", ["show", "FB-IDEEP", "--format", "json"]),
            .init("show-events-empty-text", ["show", "FB-IDEEP"]),
        ],
    ])

    private static let showLinks: [GoldenCase] = [
        .init("show-link-json", ["show", consoleLink, "--format", "json"]),
        .init("show-link-text", ["show", consoleLink]),
        .init("show-link-event-json", ["show", "\(consoleLink)?sessionEventKey=E2_1662682800563319436", "--format", "json"]),
        .init("show-link-event-text", ["show", "\(consoleLink)?sessionEventKey=E2_1662682800563319436"]),
        .init("show-link-event-missing-json", ["show", "\(consoleLink)?sessionEventKey=NOPE_1", "--format", "json"]),
        .init("show-link-event-missing-text", ["show", "\(consoleLink)?sessionEventKey=NOPE_1"]),
        .init("show-link-widget-json", [
            "show", "https://console.firebase.google.com/project/golden/crashlytics/app/ios:com.example.app.widget/issues/I3", "--format", "json",
        ]),
        .init("show-link-unknown-app-json", [
            "show", "https://console.firebase.google.com/project/golden/crashlytics/app/ios:com.other/issues/I1", "--format", "json",
        ]),
        .init("show-link-unknown-app-text", [
            "show", "https://console.firebase.google.com/project/golden/crashlytics/app/ios:com.other/issues/I1",
        ]),
    ]

    private static let showXcode: [GoldenCase] = [
        .init("show-xc-text", ["show", xcode, "--crash-directory", crashDir]),
        .init("show-xc-json", ["show", xcode, "--crash-directory", crashDir, "--format", "json"]),
        .init("show-xc-ips-text", ["show", xcodeIPS, "--crash-directory", crashDir]),
        .init("show-xc-ips-json", ["show", xcodeIPS, "--crash-directory", crashDir, "--format", "json"]),
        .init("show-xc-organizer-text", ["show", xcode]),
        .init("show-xc-widget-app-profile-json", ["show", "XC-77777777-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "--format", "json"]),
        .init("show-xc-organizer-json", ["show", xcodeIPS, "--format", "json"]),
        .init("show-xc-widget-json", ["show", "XC-77777777-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "--format", "json"], world: .widget),
        .init("show-xc-frame-filter-json", ["show", xcode, "--crash-directory", crashDir, "--app-frames-only", "--format", "json"]),
        .init("show-xc-frame-filter-text", ["show", xcode, "--crash-directory", crashDir, "--no-system-frames", "--breadcrumbs"]),
        .init("show-xc-mixed-json", ["show", xcode, "--crash-directory", GoldenWorld.mixedCrashDirectory, "--format", "json"]),
        .init("show-xc-mixed-text", ["show", xcode, "--crash-directory", GoldenWorld.mixedCrashDirectory]),
        .init("show-xc-unknown-json", ["show", "XC-NOPE", "--crash-directory", crashDir, "--format", "json"]),
        .init("show-xc-unknown-text", ["show", "XC-NOPE", "--crash-directory", crashDir]),
        .init("show-xc-no-bundle-json", ["show", xcode, "--format", "json"], world: GoldenWorld(config: .noBundleId)),
        .init("show-xc-no-config-text", ["show", xcode], world: .noConfig),
        .init("show-bad-prefix-json", ["show", "ZZ-1", "--format", "json"]),
    ]

    static let export: [GoldenCase] = .flatten([exportFirebase, exportOutput, exportXcode])

    private static let exportFirebase: [GoldenCase] = .flatten([
        .formats("export", ["export", fatal], ["markdown", "json"]),
        .formats("export-nonfatal", ["export", nonFatal], ["markdown", "json"]),
        .formats("export-no-crashed-thread", ["export", noCrashedThread], ["markdown", "json"]),
        .formats("export-event", ["export", "\(fatal)/events/E2"], ["markdown", "json"]),
        .formats("export-since-30d", ["export", fatal, "--since", "30d"], ["markdown", "json"]),
        .formats("export-app-frames-only", ["export", fatal, "--app-frames-only"], ["markdown", "json"]),
        [
            .init("export-default-md", ["export", fatal]),
            .init("export-since-all-json", ["export", fatal, "--since", "all", "--format", "json"]),
            .init("export-no-system-frames-md", ["export", fatal, "--no-system-frames"]),
            .init("export-crashing-thread-md", ["export", fatal, "--crashing-thread-only"]),
            .init("export-crashing-thread-nonfatal-json", ["export", nonFatal, "--crashing-thread-only", "--format", "json"]),
            .init("export-crashing-thread-nonfatal-md", ["export", nonFatal, "--crashing-thread-only"]),
            .init("export-link-md", ["export", consoleLink]),
            .init("export-link-event-json", ["export", "\(consoleLink)?sessionEventKey=E2_1", "--format", "json"]),
            .init("export-impact-unavailable-json", ["export", "FB-IDEEP", "--format", "json"], world: GoldenWorld(endlessIssuePages: true)),
            .init("export-impact-unavailable-md", ["export", "FB-IDEEP"], world: GoldenWorld(endlessIssuePages: true)),
            .init("export-impact-missing-md", ["export", "FB-IDEEP"]),
            .init("export-breakdown-unavailable-json", [
                "export", fatal, "--format", "json",
            ], world: GoldenWorld(failingReports: ["topOperatingSystems", "topAppleDevices"])),
            .init("export-breakdown-unavailable-md", ["export", fatal], world: GoldenWorld(failingReports: ["topAppleDevices"])),
            .init("export-widget-profile-md", ["export", fatal], world: .widget),
        ],
    ])

    private static let exportOutput: [GoldenCase] = [
        .init("export-output-md", ["export", fatal, "--output", "/tmp/golden/crash.md"]),
        .init("export-output-json", ["export", fatal, "--format", "json", "--output", "/tmp/golden/crash.json"]),
        .init("export-output-xc", ["export", xcode, "--crash-directory", crashDir, "--output", "/tmp/golden/xc.md"]),
        .init("export-format-ndjson-rejected", ["export", fatal, "--format", "ndjson"]),
        .init("export-format-text-rejected", ["export", fatal, "--format", "text"]),
    ]

    private static let exportXcode: [GoldenCase] = [
        .init("export-xc-md", ["export", xcode, "--crash-directory", crashDir]),
        .init("export-xc-json", ["export", xcode, "--crash-directory", crashDir, "--format", "json"]),
        .init("export-xc-ips-md", ["export", xcodeIPS, "--crash-directory", crashDir]),
        .init("export-xc-ips-json", ["export", xcodeIPS, "--crash-directory", crashDir, "--format", "json"]),
        .init("export-xc-organizer-md", ["export", xcode]),
        .init("export-xc-frame-filter-json", ["export", xcode, "--crash-directory", crashDir, "--app-frames-only", "--format", "json"]),
        .init("export-xc-unknown-json", ["export", "XC-NOPE", "--crash-directory", crashDir, "--format", "json"]),
        .init("export-xc-unknown-md", ["export", "XC-NOPE", "--crash-directory", crashDir]),
    ]
}
