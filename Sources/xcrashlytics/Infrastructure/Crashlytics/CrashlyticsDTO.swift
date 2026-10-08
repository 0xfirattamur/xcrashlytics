import Foundation

// Crashlytics quirk: v1alpha carries no compatibility promise, so one malformed list element
// (issue, event, thread, frame) is dropped instead of failing the whole page.
enum CrashlyticsDTO {
    struct TopIssuesResponse: Decodable, Sendable, Equatable {
        @LossyList var groups: [IssueReportGroup]
        var nextPageToken: String?
    }

    struct IssueReportGroup: Decodable, Sendable, Equatable {
        var issue: Issue
        @LossyList var metrics: [IssueReportMetrics]
    }

    struct IssueReportMetrics: Decodable, Sendable, Equatable {
        var eventsCount: FlexibleInt?
        var impactedUsersCount: FlexibleInt?
        var totalUsersCount: FlexibleInt?
        // With a granularity the first point is the whole window, the rest are one per UTC day.
        var startTime: String?
        var endTime: String?
    }

    struct TopVersionsResponse: Decodable, Sendable, Equatable {
        @LossyList var groups: [VersionReportGroup]
        var nextPageToken: String?
    }

    struct VersionReportGroup: Decodable, Sendable, Equatable {
        var version: Version?
        @LossyList var metrics: [IssueReportMetrics]
    }

    struct Issue: Decodable, Sendable, Equatable {
        var id: String
        var title: String?
        var subtitle: String?
        var errorType: String?
        var state: String?
        var uri: String?
        var firstSeenVersion: String?
        var lastSeenVersion: String?
        @LossyList var signals: [Signal]
        var name: String?

        struct Signal: Decodable, Sendable, Equatable {
            var signal: String?
            var description: String?
        }
    }

    struct EventsResponse: Sendable, Equatable {
        var events: [Event]
        var nextPageToken: String?
    }

    struct Event: Decodable, Sendable, Equatable {
        var name: String?
        var platform: String?
        var eventId: String?
        var eventTime: String?
        var bundleOrPackage: String?
        var issue: EventIssue?
        var issueTitle: String?
        var issueSubtitle: String?
        var processState: String?
        var version: Version?
        var device: Device?
        var operatingSystem: OperatingSystem?
        var memory: Resource?
        var storage: Resource?
        var user: User?
        var blameFrame: Frame?
        @LossyList var exceptions: [Exception]
        @LossyList var threads: [Thread]
        @LossyList var errors: [Exception]
        var customKeys: StringMap?
        @LossyList var logs: [Log]
        @LossyList var breadcrumbs: [Breadcrumb]
        // Attached after decoding, never on the wire.
        var rawJSON: String?
    }

    struct EventIssue: Decodable, Sendable, Equatable {
        var id: String?
        var name: String?
        var title: String?
        var subtitle: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, title, subtitle
        }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self.id = value.split(separator: "/").last.map(String.init) ?? value
                self.name = value
                return
            }
            let object = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try object.decodeIfPresent(String.self, forKey: .id)
            self.name = try object.decodeIfPresent(String.self, forKey: .name)
            self.title = try object.decodeIfPresent(String.self, forKey: .title)
            self.subtitle = try object.decodeIfPresent(String.self, forKey: .subtitle)
        }
    }

    struct Version: Decodable, Sendable, Equatable {
        var displayVersion: String?
        var buildVersion: String?
        var displayName: String?
    }

    struct Device: Decodable, Sendable, Equatable {
        var model: String?
        var orientation: String?
    }

    struct OperatingSystem: Decodable, Sendable, Equatable {
        var displayVersion: String?
        var jailbroken: Bool?
        var orientation: String?
    }

    struct Resource: Decodable, Sendable, Equatable {
        var free: FlexibleInt?
        var used: FlexibleInt?
    }

    struct User: Decodable, Sendable, Equatable {
        var id: String?
    }

    struct Thread: Decodable, Sendable, Equatable {
        var name: String?
        var title: String?
        var subtitle: String?
        var crashed: Bool?
        var blamed: Bool?
        var signal: String?
        var signalCode: String?
        var crashAddress: FlexibleString?
        var queue: String?
        @LossyList var frames: [Frame]
    }

    struct Log: Decodable, Sendable, Equatable {
        var logTime: String?
        var message: String?
    }

    struct Breadcrumb: Decodable, Sendable, Equatable {
        var eventTime: String?
        var title: String?
        var params: StringMap?
    }

    // Also decodes Apple non-fatal `errors[]` entries.
    struct Exception: Decodable, Sendable, Equatable {
        var type: String?
        var exceptionMessage: String?
        var title: String?
        var subtitle: String?
        var blamed: Bool?
        @LossyList var frames: [Frame]
    }

    struct Frame: Decodable, Sendable, Equatable {
        var symbol: String?
        var file: String?
        var line: FlexibleInt?
        var column: FlexibleInt?
        var address: FlexibleAddress?
        var library: String?
        var owner: String?
        var blamed: Bool?
        var offset: FlexibleInt?
    }
}
