import Foundation

extension GoldenCases {
    static let events: [GoldenCase] = .flatten([eventsListing, eventsFrames, eventsFilters, eventsDsym])

    private static let eventsListing: [GoldenCase] = .flatten([
        .formats("events", ["events", fatal]),
        .formats("events-latest", ["events", fatal, "--latest"]),
        .formats("events-nonfatal", ["events", nonFatal]),
        .formats("events-no-crashed-thread", ["events", noCrashedThread], ["text", "json"]),
        [
            .init("events-limit-1-json", ["events", fatal, "--limit", "1", "--format", "json"]),
            .init("events-two-issues-json", ["events", "\(fatal),\(nonFatal)", "--format", "json"]),
            .init("events-two-issues-text", ["events", "\(fatal),\(nonFatal)"]),
            .init("events-two-issues-ndjson", ["events", "\(fatal),\(nonFatal)", "--format", "ndjson"]),
            .init("events-issues-flag-json", ["events", "--issues", "\(fatal),FB-I3", "--format", "json"]),
            .init("events-event-id-json", ["events", "\(fatal)/events/E2", "--format", "json"]),
            .init("events-event-id-text", ["events", "\(fatal)/events/E2"]),
            .init("events-event-missing-json", ["events", "\(fatal)/events/NOPE", "--format", "json"]),
            .init("events-lowercase-id-json", ["events", "fb-I1", "--latest", "--format", "json"]),
            .init("events-since-7d-json", ["events", fatal, "--since", "7d", "--format", "json"]),
            .init("events-since-30d-text", ["events", fatal, "--since", "30d"]),
            .init("events-since-all-json", ["events", fatal, "--since", "all", "--format", "json"]),
            .init("events-widget-profile-json", ["events", fatal, "--latest", "--format", "json"], world: .widget),
            .init("events-empty-issue-json", ["events", "FB-IEMPTY", "--format", "json"]),
            .init("events-empty-issue-text", ["events", "FB-IEMPTY"]),
        ],
    ])

    private static let eventsFrames: [GoldenCase] = .flatten([
        .formats("events-frames-only", ["events", fatal, "--frames-only"]),
        .formats("events-app-frames-only", ["events", fatal, "--app-frames-only"]),
        .formats("events-no-system-frames", ["events", fatal, "--no-system-frames"], ["text", "json"]),
        .formats("events-crashing-thread-only", ["events", fatal, "--crashing-thread-only"], ["text", "json"]),
        .formats("events-breadcrumbs", ["events", fatal, "--latest", "--breadcrumbs"], ["text", "json", "ndjson"]),
        [
            .init("events-breadcrumbs-frames-only-json", ["events", fatal, "--latest", "--breadcrumbs", "--frames-only", "--format", "json"]),
            .init("events-nonfatal-app-frames-json", ["events", nonFatal, "--app-frames-only", "--format", "json"]),
            .init("events-nonfatal-app-frames-text", ["events", nonFatal, "--app-frames-only"]),
            .init("events-nonfatal-no-system-json", ["events", nonFatal, "--no-system-frames", "--format", "json"]),
            .init("events-nonfatal-crashing-thread-json", ["events", nonFatal, "--crashing-thread-only", "--format", "json"]),
            .init("events-nonfatal-crashing-thread-text", ["events", nonFatal, "--crashing-thread-only"]),
            .init("events-nonfatal-crashing-thread-ndjson", ["events", nonFatal, "--crashing-thread-only", "--format", "ndjson"]),
            .init("events-no-crashed-thread-only-json", ["events", noCrashedThread, "--crashing-thread-only", "--format", "json"]),
            .init("events-no-crashed-thread-app-frames-json", ["events", noCrashedThread, "--app-frames-only", "--format", "json"]),
            .init("events-all-frame-filters-json", [
                "events", fatal, "--app-frames-only", "--no-system-frames", "--crashing-thread-only", "--format", "json",
            ]),
            .init("events-app-libraries-absent-json", ["events", fatal, "--app-frames-only", "--format", "json"], world: .noConfigAppId),
        ],
    ])

    private static let eventsFilters: [GoldenCase] = [
        .init("events-user-id-json", ["events", fatal, "--user-id", "user-secret-1", "--format", "json"]),
        .init("events-user-id-text", ["events", fatal, "--user-id", "user-secret-1"]),
        .init("events-user-id-other-json", ["events", fatal, "--user-id", "user-other-2", "--format", "json"]),
        .init("events-user-id-none-json", ["events", fatal, "--user-id", "nobody", "--format", "json"]),
        .init("events-user-id-none-text", ["events", fatal, "--user-id", "nobody"]),
        .init("events-user-id-truncated-json", ["events", "FB-IMANY", "--user-id", "nobody", "--format", "json"]),
        .init("events-user-id-truncated-text", ["events", "FB-IMANY", "--user-id", "nobody"]),
        .init("events-user-id-truncated-ndjson", ["events", "FB-IMANY", "--user-id", "nobody", "--format", "ndjson"]),
        .init("events-user-id-limit-json", ["events", "FB-IMANY", "--user-id", "user-other-2", "--limit", "2", "--format", "json"]),
        .init("events-many-limit-3-json", ["events", "FB-IMANY", "--limit", "3", "--format", "json"]),
        .init("events-many-default-limit-text", ["events", "FB-IMANY"]),
    ]

    private static let eventsDsym: [GoldenCase] = [
        .init("events-dsym-json", ["events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory, "--format", "json"]),
        .init("events-dsym-text", ["events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory]),
        .init("events-dsym-ndjson", ["events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory, "--format", "ndjson"]),
        .init("events-dsym-bundle-json", [
            "events", fatal, "--latest", "--dsym", "\(GoldenWorld.dsymDirectory)/KeyboardCore.framework.dSYM", "--format", "json",
        ]),
        .init("events-dsym-frames-only-json", ["events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory, "--frames-only", "--format", "json"]),
        .init("events-dsym-atos-fails-json", [
            "events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory, "--format", "json",
        ], world: GoldenWorld(dsymTools: .atosFails)),
        .init("events-dsym-otool-fails-text", ["events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory], world: GoldenWorld(dsymTools: .otoolFails)),
        .init("events-dsym-missing-json", ["events", fatal, "--latest", "--dsym", "/empty-dsyms", "--format", "json"]),
        .init("events-dsym-missing-text", ["events", fatal, "--latest", "--dsym", "/empty-dsyms"]),
        .init("events-dsym-two-paths-json", [
            "events", fatal, "--latest", "--dsym", GoldenWorld.dsymDirectory, "--dsym", "/empty-dsyms", "--format", "json",
        ]),
        .init("events-dsym-other-issue-json", ["events", nonFatal, "--dsym", GoldenWorld.dsymDirectory, "--format", "json"]),
    ]
}

extension GoldenWorld {
    /// Only a top-level `appId`: no profile, so no `appLibraries`.
    static let noConfigAppId = GoldenWorld(config: .appIdOnly)
}
