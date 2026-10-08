import Foundation

/// Synthetic `reports/*` and `issues/*` bodies, built as JSON objects so key order never matters.
enum GoldenReports {
    struct Issue {
        var id: String
        var title: String
        var subtitle: String
        var errorType: String
        var signal: String
        var firstSeen: String
        var lastSeen: String
        var events: Int
        var users: Int
    }

    static let issues = [
        Issue(id: "I1", title: "[ExampleApp] BlurService.swift - BlurService.classify(_:)", subtitle: "Fatal error: Array index out of range",
              errorType: "FATAL", signal: "SIGABRT", firstSeen: "6.14.2", lastSeen: "6.16.0", events: 42, users: 12),
        Issue(id: "I2", title: "[Core] FIRCLSNonFatalError.m - -[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]",
              subtitle: "Domain: com.example.NetworkError", errorType: "NON_FATAL", signal: "", firstSeen: "6.15.0", lastSeen: "6.16.0",
              events: 17, users: 9),
        Issue(id: "I3", title: "[ExampleApp] MapRenderer.swift - MapRenderer.draw(_:)", subtitle: "EXC_BAD_ACCESS",
              errorType: "EXC_BAD_ACCESS", signal: "SIGSEGV", firstSeen: "6.15.0", lastSeen: "6.15.0", events: 9, users: 4),
        Issue(id: "I4", title: "[KeyboardCore] objectdestroyTm", subtitle: "KERN_INVALID_ADDRESS",
              errorType: "FATAL", signal: "SIGSEGV", firstSeen: "6.16.0", lastSeen: "6.16.0", events: 6, users: 3),
        Issue(id: "I5", title: "[ExampleApp] BlurService.swift - BlurService.classify(_:)", subtitle: "Fatal error: Unexpectedly found nil",
              errorType: "FATAL", signal: "SIGABRT", firstSeen: "6.16.0", lastSeen: "6.16.0", events: 3, users: 2),
    ]

    /// An issue that exists but never appears in the topIssues ranking.
    static let unrankedIssue = Issue(
        id: "IDEEP", title: "[ExampleApp] Legacy.swift - Legacy.run()", subtitle: "Fatal error", errorType: "FATAL",
        signal: "SIGABRT", firstSeen: "6.10.0", lastSeen: "6.10.0", events: 1, users: 1)

    /// Events and users per issue and version, for the `filter.version.displayNames` reports.
    static let perVersion: [String: [String: (events: Int, users: Int)]] = [
        "6.16.0 (937)": ["I1": (30, 9), "I2": (12, 7), "I4": (6, 3), "I5": (3, 2)],
        "6.15.0 (900)": ["I1": (12, 6), "I2": (5, 3), "I3": (9, 4)],
    ]

    static let days = ["2026-06-09", "2026-06-10", "2026-06-11", "2026-06-12", "2026-06-13", "2026-06-14", "2026-06-15"]
    static let dailyCounts: [String: [Int]] = [
        "I1": [0, 3, 6, 9, 12, 8, 4],
        "I2": [1, 0, 4, 2, 5, 3, 2],
    ]

    static func url(for issueId: String) -> String {
        "https://console.firebase.google.com/project/golden/crashlytics/app/ios:com.example.app/issues/\(issueId)"
    }

    static func issueObject(_ issue: Issue) -> [String: Any] {
        var object: [String: Any] = [
            "id": issue.id,
            "title": issue.title,
            "subtitle": issue.subtitle,
            "errorType": issue.errorType,
            "state": "OPEN",
            "sampleEvent": "projects/1234567890/apps/\(GoldenWorld.appId)/events/SESS_\(issue.id)",
            "uri": url(for: issue.id),
            "firstSeenVersion": issue.firstSeen,
            "lastSeenVersion": issue.lastSeen,
        ]
        if !issue.signal.isEmpty { object["signals"] = [["signal": issue.signal, "description": "\(issue.signal) description"]] }
        return object
    }

    private static func metric(events: Int, users: Int, total: Int? = nil, start: String? = nil) -> [String: Any] {
        var object: [String: Any] = ["eventsCount": String(events), "impactedUsersCount": String(users)]
        if let total { object["totalUsersCount"] = String(total) }
        if let start {
            object["startTime"] = start + "T00:00:00Z"
            object["endTime"] = start + "T23:59:59Z"
        }
        return object
    }

    /// `reports/topIssues`: all issues, or the version-filtered counts, with optional daily series.
    static func topIssues(versionNames: [String], daily: Bool) -> [String: Any] {
        var groups: [[String: Any]] = []
        for issue in issues {
            var events = issue.events
            var users = issue.users
            if !versionNames.isEmpty {
                let matched = versionNames.compactMap { perVersion[$0]?[issue.id] }
                guard !matched.isEmpty else { continue }
                events = matched.reduce(0) { $0 + $1.events }
                users = matched.reduce(0) { $0 + $1.users }
            }
            var metrics = [metric(events: events, users: users, total: 900)]
            if daily {
                let counts = dailyCounts[issue.id] ?? [0, 0, 0, 0, 0, 0, 0]
                metrics += zip(days, counts).map { metric(events: $1, users: 0, start: $0) }
            }
            groups.append(["issue": issueObject(issue), "metrics": metrics])
        }
        return ["groups": groups]
    }

    private static func version(_ display: String, _ build: String) -> [String: Any] {
        ["displayVersion": display, "buildVersion": build, "displayName": "\(display) (\(build))"]
    }

    /// `reports/topVersions`: app-wide, issue-scoped, or an issue's daily series per version.
    static func topVersions(issueId: String?, daily: Bool) -> [String: Any] {
        let versions = [("6.16.0", "937", 900), ("6.15.0", "900", 600), ("6.14.2", "880", 120), ("6.13.0", "850", 0)]
        var groups: [[String: Any]] = []
        for (display, build, population) in versions {
            let name = "\(display) (\(build))"
            var whole: [String: Any]
            if let issueId {
                let counts = perVersion[name]?[issueId] ?? (0, 0)
                whole = metric(events: counts.events, users: counts.users, total: population)
            } else {
                whole = metric(events: population / 20, users: population / 60, total: population)
                whole["sessionsCount"] = String(population * 3)
                whole["totalSessionsCount"] = String(population * 3)
                whole["crashFreeUsersPercentage"] = 99.25
            }
            var metrics = [whole]
            if daily, let issueId {
                let counts = dailyCounts[issueId] ?? [0, 0, 0, 0, 0, 0, 0]
                let share = name == "6.16.0 (937)" ? 1 : 0
                metrics += zip(days, counts).map { metric(events: $1 * share, users: 0, start: $0) }
            }
            groups.append(["version": version(display, build), "metrics": metrics])
        }
        return ["groups": groups]
    }

    static func topOperatingSystems(issueId: String?) -> [String: Any] {
        let rows = [("17.5.1", 20, 7, 700), ("17.4", 14, 5, 500), ("16.7.8", 6, 3, 150), ("15.8", 0, 0, 20)]
        let groups = rows.map { version, events, users, population -> [String: Any] in
            var metrics = metric(events: events, users: users, total: population)
            if issueId == nil { metrics["crashFreeUsersPercentage"] = 98.5 }
            return [
                "operatingSystem": ["os": "iOS", "displayVersion": version, "displayName": "iOS \(version)"],
                "metrics": [metrics],
            ]
        }
        return ["groups": groups]
    }

    static func topAppleDevices(issueId: String?) -> [String: Any] {
        func model(_ identifier: String, _ marketing: String, _ events: Int, _ users: Int, _ population: Int) -> [String: Any] {
            var metrics = metric(events: events, users: users, total: population)
            if issueId == nil { metrics["crashFreeUsersPercentage"] = 97.75 }
            return [
                "device": ["manufacturer": "Apple", "model": identifier, "displayName": "\(marketing) (\(identifier))", "marketingName": marketing],
                "metrics": [metrics],
            ]
        }
        let apple: [String: Any] = [
            "device": ["manufacturer": "Apple", "displayName": "Apple"],
            "metrics": [metric(events: 40, users: 12, total: 800)],
            "subgroups": [
                model("iPhone15,2", "iPhone 14 Pro", 24, 8, 400),
                model("iPhone14,5", "iPhone 13", 12, 6, 300),
                model("iPad13,1", "iPad Air", 4, 2, 100),
                model("iPhone12,1", "iPhone 11", 0, 0, 40),
            ],
        ]
        return ["groups": [apple]]
    }
}
