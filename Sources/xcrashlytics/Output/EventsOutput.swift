import Foundation

// MARK: - IssueEvents

struct IssueEvents: Sendable {
    var issueId: String
    var events: [FirebaseEvent]

}

// MARK: - EventsRenderer

enum EventsRenderer {
    static func text(
        _ issueEvents: [IssueEvents],
        frameOptions: FirebaseFrameFilterOptions
    ) -> String {
        let rows = issueEvents.flatMap { group in
            group.events.map { event -> String in
                let id = FirebaseIdentifiers.canonicalEventId(event, issueId: group.issueId)
                let frame = FirebaseEventFrames.topFrameDescription(for: event, options: frameOptions) ?? "no frames"
                return (summarySegments(for: event, id: id) + [memorySummary(for: event), frame])
                    .compactMap { $0 }
                    .joined(separator: "   ")
            }
        }
        guard !rows.isEmpty else {
            return "No Firebase events found for \(issueEvents.map(\.issueId).joined(separator: ", ")).\n"
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func framesOnlyText(
        _ issueEvents: [IssueEvents],
        frameOptions: FirebaseFrameFilterOptions
    ) -> String {
        let rows = issueEvents.flatMap { group in
            group.events.map { event in
                let eventId = FirebaseIdentifiers.canonicalEventId(event, issueId: group.issueId)
                let frames = FirebaseEventFrames.filteredFrames(from: event, options: frameOptions)
                guard !frames.isEmpty else {
                    return frameOptions.appFramesOnly
                        ? "No app-owned frames found for \(eventId). Retry without --app-frames-only or run xcrashlytics blame."
                        : "\(eventId) has no frames."
                }
                let rendered = frames.enumerated().map { index, frame in
                    let marker = FirebaseEventFrames.isBlamed(frame, in: event) ? "*" : " "
                    let location = FirebaseEventFrames.location(for: frame)
                    let symbol = frame.symbol ?? "?"
                    return "  \(marker) \(index) \(location) \(symbol)"
                }
                let header = summarySegments(for: event, id: eventId).compactMap { $0 }.joined(separator: "   ")
                return ([header] + rendered).joined(separator: "\n")
            }
        }
        guard !rows.isEmpty else {
            return "No Firebase events found for \(issueEvents.map(\.issueId).joined(separator: ", ")).\n"
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func ndjson(
        _ issueEvents: [IssueEvents],
        framesOnly: Bool,
        frameOptions: FirebaseFrameFilterOptions
    ) throws -> String {
        if framesOnly {
            return try PayloadEncoder.ndjson(issueEvents.flatMap { group in
                group.events.map { EventFramesOnlySummary($0, issueId: group.issueId, options: frameOptions) }
            })
        }
        return try PayloadEncoder.ndjson(issueEvents.flatMap { group in
            group.events.map { EventSummary($0, issueId: group.issueId, options: frameOptions) }
        })
    }

    static func json(
        _ issueEvents: [IssueEvents],
        framesOnly: Bool,
        frameOptions: FirebaseFrameFilterOptions,
        scannedEvents: Int? = nil,
        warnings: [CLIWarning] = []
    ) throws -> String {
        if framesOnly {
            return try PayloadEncoder.envelope(EventsFramesOnlyPayload(
                events: issueEvents.flatMap { group in
                    group.events.map { EventFramesOnlySummary($0, issueId: group.issueId, options: frameOptions) }
                },
                scannedEvents: scannedEvents
            ), warnings: warnings)
        }
        return try PayloadEncoder.envelope(EventsPayload(
            events: issueEvents.flatMap { group in
                group.events.map { EventSummary($0, issueId: group.issueId, options: frameOptions) }
            },
            scannedEvents: scannedEvents
        ), warnings: warnings)
    }

    // MARK: - Private helpers

    private static func summarySegments(for event: FirebaseEvent, id: String) -> [String?] {
        [id, event.eventTime ?? "unknown time", appVersion(for: event), runtimeSummary(for: event)]
    }

    private static func appVersion(for event: FirebaseEvent) -> String? {
        switch (event.displayVersion, event.buildVersion) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "build \(build)"
        case (nil, nil):
            return nil
        }
    }

    private static func runtimeSummary(for event: FirebaseEvent) -> String? {
        let device = event.deviceModel
        let os = event.osVersion.map { "iOS \($0)" }
        let parts = [device, os].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private static func memorySummary(for event: FirebaseEvent) -> String? {
        guard let bytes = event.memoryFree else { return nil }
        return "\(mibString(bytes)) free RAM"
    }

    private static func mibString(_ bytes: Int) -> String {
        String(format: "%.2f MiB", Double(bytes) / 1_048_576.0)
    }
}

// MARK: - Payload types

struct EventsPayload: Encodable, Sendable {
    var events: [EventSummary]
    var scannedEvents: Int?

    init(events: [EventSummary], scannedEvents: Int? = nil) {
        self.events = events
        self.scannedEvents = scannedEvents
    }
}

struct EventsFramesOnlyPayload: Encodable, Sendable {
    var events: [EventFramesOnlySummary]
    var scannedEvents: Int?

    init(events: [EventFramesOnlySummary], scannedEvents: Int? = nil) {
        self.events = events
        self.scannedEvents = scannedEvents
    }
}

struct EventFramesOnlySummary: Encodable, Sendable {
    var id: String
    var firebaseEventId: String
    var issueId: String
    var eventTime: String?
    var blamedFrame: FrameSummary?
    var frames: [FrameSummary]

    init(
        _ event: FirebaseEvent,
        issueId: String,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) {
        let frames = FirebaseEventFrames.filteredFrames(from: event, options: options).enumerated().map { index, frame in
            FrameSummary(index: index, frame: frame, isBlamed: FirebaseEventFrames.isBlamed(frame, in: event))
        }
        self.id = FirebaseIdentifiers.canonicalEventId(event, issueId: issueId)
        self.firebaseEventId = event.eventId ?? "unknown"
        self.issueId = FirebaseIdentifiers.canonicalIssueId(issueId)
        self.eventTime = event.eventTime
        self.blamedFrame = frames.first(where: { $0.isBlamed }) ?? frames.first
        self.frames = frames
    }
}

struct EventSummary: Encodable, Sendable {
    var id: String
    var firebaseEventId: String
    var issueId: String
    var eventTime: String?
    var appVersion: String?
    var appBuild: String?
    var deviceModel: String?
    var deviceOrientation: String?
    var osVersion: String?
    var osOrientation: String?
    var isJailbroken: Bool?
    var memoryFreeBytes: Int?
    var memoryUsedBytes: Int?
    var storageFreeBytes: Int?
    var storageUsedBytes: Int?
    var userIdHash: String?
    var processState: String?
    var frames: [FrameSummary]

    init(
        _ event: FirebaseEvent,
        issueId: String,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) {
        self.id = FirebaseIdentifiers.canonicalEventId(event, issueId: issueId)
        self.firebaseEventId = event.eventId ?? "unknown"
        self.issueId = FirebaseIdentifiers.canonicalIssueId(issueId)
        self.eventTime = event.eventTime
        self.appVersion = event.displayVersion
        self.appBuild = event.buildVersion
        self.deviceModel = event.deviceModel
        self.deviceOrientation = event.deviceOrientation
        self.osVersion = event.osVersion
        self.osOrientation = event.osOrientation
        self.isJailbroken = event.jailbroken
        self.memoryFreeBytes = event.memoryFree
        self.memoryUsedBytes = event.memoryUsed
        self.storageFreeBytes = event.storageFree
        self.storageUsedBytes = event.storageUsed
        self.userIdHash = event.userId.map(Hashing.sha256Hex)
        self.processState = event.processState
        self.frames = FirebaseEventFrames.filteredFrames(from: event, options: options).enumerated().map { index, frame in
            FrameSummary(index: index, frame: frame, isBlamed: FirebaseEventFrames.isBlamed(frame, in: event))
        }
    }
}

struct FrameSummary: Encodable, Sendable {
    var index: Int
    var binaryName: String
    var symbol: String?
    var file: String?
    var line: Int?
    var isBlamed: Bool

    init(index: Int, frame: FirebaseFrame, isBlamed: Bool? = nil) {
        self.index = index
        self.binaryName = frame.library ?? "?"
        self.symbol = frame.symbol
        self.file = frame.file
        self.line = frame.line
        self.isBlamed = isBlamed ?? frame.blamed
    }
}
