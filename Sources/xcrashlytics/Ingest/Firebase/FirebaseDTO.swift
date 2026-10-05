//
//  FirebaseDTO.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Wire-level types that mirror `firebasecrashlytics.googleapis.com/v1alpha`
/// (the same schema documented at firebase.google.com/docs/reference/crashlytics/rest).
/// Internal: callers see `CrashIssue` / `FirebaseEvent`, never wire shapes.
enum FirebaseDTO {
    // MARK: - topIssues report

    /// Response from `reports/topIssues`.
    struct TopIssuesResponse: Codable, Sendable, Equatable {
        let groups: [IssueGroup]?
        let nextPageToken: String?
    }

    /// One row in the topIssues report — issue + its metrics.
    struct IssueGroup: Codable, Sendable, Equatable {
        let issue: IssueDTO
        let metrics: [IssueMetrics]?
    }

    /// Counts associated with an issue at the top-N level.
    struct IssueMetrics: Codable, Sendable, Equatable {
        let eventsCount: String?
        let impactedUsersCount: String?
    }

    // MARK: - Issue

    /// A single Crashlytics issue.
    struct IssueDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String?
        let subtitle: String?
        let errorType: String?
        let state: String?
        let sampleEvent: String?
        let uri: String?
        let firstSeenVersion: String?
        let lastSeenVersion: String?
        let signals: [Signal]?
        let name: String?

        struct Signal: Codable, Sendable, Equatable {
            let signal: String?
            let description: String?
        }
    }

    // MARK: - Event

    /// Response from `events` (events.list).
    struct EventsResponse: Codable, Sendable, Equatable {
        let events: [EventDTO]?
        let nextPageToken: String?
    }

    /// A single event from `events.list`.
    struct EventDTO: Codable, Sendable, Equatable {
        let name: String?
        let platform: String?
        let eventId: String?
        let eventTime: String?
        let bundleOrPackage: String?
        let issue: EventIssueDTO?
        let issueTitle: String?
        let issueSubtitle: String?
        let processState: String?
        let version: VersionDTO?
        let device: DeviceDTO?
        let operatingSystem: OperatingSystemDTO?
        let memory: ResourceDTO?
        let storage: ResourceDTO?
        let user: UserDTO?
        let blameFrame: FrameDTO?
        let exceptions: [ExceptionDTO]?
        let threads: [ThreadDTO]?
        let rawJSON: String?
    }

    struct EventIssueDTO: Codable, Sendable, Equatable {
        let id: String?
        let name: String?
        let title: String?
        let subtitle: String?
        let rawValue: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case title
            case subtitle
            case rawValue
        }

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let value = try? single.decode(String.self) {
                self.id = value.split(separator: "/").last.map(String.init) ?? value
                self.name = value
                self.title = nil
                self.subtitle = nil
                self.rawValue = value
                return
            }

            let object = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try object.decodeIfPresent(String.self, forKey: .id)
            self.name = try object.decodeIfPresent(String.self, forKey: .name)
            self.title = try object.decodeIfPresent(String.self, forKey: .title)
            self.subtitle = try object.decodeIfPresent(String.self, forKey: .subtitle)
            self.rawValue = nil
        }

        func encode(to encoder: Encoder) throws {
            var object = encoder.container(keyedBy: CodingKeys.self)
            try object.encodeIfPresent(id, forKey: .id)
            try object.encodeIfPresent(name, forKey: .name)
            try object.encodeIfPresent(title, forKey: .title)
            try object.encodeIfPresent(subtitle, forKey: .subtitle)
            try object.encodeIfPresent(rawValue, forKey: .rawValue)
        }
    }

    struct VersionDTO: Codable, Sendable, Equatable {
        let displayVersion: String?
        let buildVersion: String?
    }

    struct DeviceDTO: Codable, Sendable, Equatable {
        let model: String?
        let orientation: String?
    }

    struct OperatingSystemDTO: Codable, Sendable, Equatable {
        let displayVersion: String?
        let jailbroken: Bool?
        let orientation: String?
    }

    struct ResourceDTO: Codable, Sendable, Equatable {
        let free: FlexibleInt?
        let used: FlexibleInt?
    }

    struct UserDTO: Codable, Sendable, Equatable {
        let id: String?
    }

    struct FlexibleInt: Codable, Sendable, Equatable {
        let intValue: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self.intValue = value
            } else if let value = try? container.decode(String.self) {
                self.intValue = Int(value)
            } else {
                self.intValue = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let intValue {
                try container.encode(intValue)
            } else {
                try container.encodeNil()
            }
        }
    }

    struct ThreadDTO: Codable, Sendable, Equatable {
        let name: String?
        let title: String?
        let crashed: Bool?
        let frames: [FrameDTO]?
    }

    struct ExceptionDTO: Codable, Sendable, Equatable {
        let type: String?
        let exceptionMessage: String?
        let title: String?
        let subtitle: String?
        let blamed: Bool?
        let frames: [FrameDTO]?
    }

    struct FrameDTO: Codable, Sendable, Equatable {
        let symbol: String?
        let file: String?
        let line: String?
        let library: String?
        let owner: String?
        let blamed: Bool?
        let offset: String?
    }
}

extension FirebaseDTO.EventsResponse {
    /// Decodes events and attaches each raw event object so callers can keep
    /// fields that are not yet promoted to typed properties.
    static func decodePreservingRawEvents(from data: Data) throws -> Self {
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        guard
            let events = decoded.events,
            let rawEvents = rawEventJSONs(from: data),
            events.count == rawEvents.count
        else {
            return decoded
        }
        return Self(
            events: zip(events, rawEvents).map { event, rawJSON in
                event.withRawJSON(rawJSON)
            },
            nextPageToken: decoded.nextPageToken
        )
    }

    private static func rawEventJSONs(from data: Data) -> [String]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let events = object["events"] as? [Any]
        else {
            return nil
        }
        return events.compactMap { event in
            guard JSONSerialization.isValidJSONObject(event) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }
}

extension FirebaseDTO.EventDTO {
    fileprivate func withRawJSON(_ rawJSON: String) -> Self {
        Self(
            name: name,
            platform: platform,
            eventId: eventId,
            eventTime: eventTime,
            bundleOrPackage: bundleOrPackage,
            issue: issue,
            issueTitle: issueTitle,
            issueSubtitle: issueSubtitle,
            processState: processState,
            version: version,
            device: device,
            operatingSystem: operatingSystem,
            memory: memory,
            storage: storage,
            user: user,
            blameFrame: blameFrame,
            exceptions: exceptions,
            threads: threads,
            rawJSON: rawJSON
        )
    }
}

extension FirebaseDTO.IssueDTO {
    /// Maps a Firebase issue to the domain issue aggregate.
    func toCrashIssue(
        eventsCount: Int? = nil,
        impactedUsersCount: Int? = nil
    ) -> CrashIssue {
        CrashIssue(
            providerId: id,
            title: title,
            subtitle: subtitle,
            exceptionType: errorType ?? title ?? "UNKNOWN",
            signal: signals?.first?.signal,
            eventsCount: eventsCount,
            impactedUsersCount: impactedUsersCount,
            firstSeenVersion: firstSeenVersion,
            lastSeenVersion: lastSeenVersion
        )
    }
}

extension FirebaseDTO.EventDTO {
    /// Flattens the wire event into the domain shape.
    func toFirebaseEvent() -> FirebaseEvent {
        FirebaseEvent(
            eventId: eventId ?? name?.split(separator: "/").last.map(String.init),
            issueId: issue?.id,
            issueTitle: issueTitle,
            issueSubtitle: issueSubtitle,
            eventTime: eventTime,
            platform: platform,
            bundleOrPackage: bundleOrPackage,
            processState: processState,
            displayVersion: version?.displayVersion,
            buildVersion: version?.buildVersion,
            deviceModel: device?.model,
            deviceOrientation: device?.orientation,
            osVersion: operatingSystem?.displayVersion,
            osOrientation: operatingSystem?.orientation,
            jailbroken: operatingSystem?.jailbroken,
            memoryFree: memory?.free?.intValue,
            memoryUsed: memory?.used?.intValue,
            storageFree: storage?.free?.intValue,
            storageUsed: storage?.used?.intValue,
            userId: user?.id,
            blameFrame: blameFrame?.toFirebaseFrame(),
            exceptions: (exceptions ?? []).map {
                FirebaseException(
                    type: $0.type, exceptionMessage: $0.exceptionMessage,
                    title: $0.title, subtitle: $0.subtitle,
                    blamed: $0.blamed == true, frames: ($0.frames ?? []).map { $0.toFirebaseFrame() })
            },
            threads: (threads ?? []).map {
                FirebaseThread(
                    name: $0.name, title: $0.title, crashed: $0.crashed == true,
                    frames: ($0.frames ?? []).map { $0.toFirebaseFrame() })
            },
            rawJSON: rawJSON
        )
    }
}

extension FirebaseDTO.FrameDTO {
    func toFirebaseFrame() -> FirebaseFrame {
        FirebaseFrame(
            symbol: symbol, file: file, line: line.flatMap(Int.init),
            library: library, owner: owner, blamed: blamed == true, offset: offset)
    }
}
