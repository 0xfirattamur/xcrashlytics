//
//  EventsOutput.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation
import XCrashlyticsCore

// MARK: - IssueEvents

public struct IssueEvents: Sendable {
    public var issueId: String
    public var events: [FirebaseEvent]

    public init(issueId: String, events: [FirebaseEvent]) {
        self.issueId = issueId
        self.events = events
    }
}

// MARK: - EventsRenderer

public enum EventsRenderer {
    public static func text(
        _ issueEvents: [IssueEvents],
        frameOptions: FirebaseFrameFilterOptions
    ) -> String {
        let rows = issueEvents.flatMap { group in
            group.events.map { event -> String in
                let id = FirebaseIdentifiers.canonicalEventId(event, issueId: group.issueId)
                let frame = FirebaseEventFrames.topFrameDescription(for: event, options: frameOptions) ?? "no frames"
                let segments = [
                    id,
                    event.eventTime ?? "unknown time",
                    appVersion(for: event),
                    runtimeSummary(for: event),
                    memorySummary(for: event),
                    frame,
                ]
                return segments.compactMap { $0 }.joined(separator: "   ")
            }
        }
        guard !rows.isEmpty else {
            return "No Firebase events found for \(issueEvents.map(\.issueId).joined(separator: ", ")).\n"
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func framesOnlyText(
        _ issueEvents: [IssueEvents],
        frameOptions: FirebaseFrameFilterOptions
    ) -> String {
        let rows = issueEvents.flatMap { group in
            group.events.map { event in
                let eventId = FirebaseIdentifiers.canonicalEventId(event, issueId: group.issueId)
                let frames = FirebaseEventFrames.frameDTOs(from: event, options: frameOptions)
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
                return ([eventId] + rendered).joined(separator: "\n")
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

public struct EventsPayload: Encodable, Sendable {
    public var events: [EventSummary]
    public var scannedEvents: Int?

    public init(events: [EventSummary], scannedEvents: Int? = nil) {
        self.events = events
        self.scannedEvents = scannedEvents
    }
}

public struct EventsFramesOnlyPayload: Encodable, Sendable {
    public var events: [EventFramesOnlySummary]
    public var scannedEvents: Int?

    public init(events: [EventFramesOnlySummary], scannedEvents: Int? = nil) {
        self.events = events
        self.scannedEvents = scannedEvents
    }
}

public struct EventFramesOnlySummary: Encodable, Sendable {
    public var id: String
    public var firebaseEventId: String
    public var issueId: String
    public var eventTime: String?
    public var blamedFrame: FrameSummary?
    public var frames: [FrameSummary]

    public init(
        _ event: FirebaseEvent,
        issueId: String,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) {
        let frames = FirebaseEventFrames.frameDTOs(from: event, options: options).enumerated().map { index, frame in
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

public struct EventSummary: Encodable, Sendable {
    public var id: String
    public var firebaseEventId: String
    public var issueId: String
    public var eventTime: String?
    public var appVersion: String?
    public var appBuild: String?
    public var deviceModel: String?
    public var deviceOrientation: String?
    public var osVersion: String?
    public var osOrientation: String?
    public var isJailbroken: Bool?
    public var memoryFreeBytes: Int?
    public var memoryUsedBytes: Int?
    public var storageFreeBytes: Int?
    public var storageUsedBytes: Int?
    public var userIdHash: String?
    public var processState: String?
    public var frames: [FrameSummary]

    public init(
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
        self.frames = FirebaseEventFrames.frameDTOs(from: event, options: options).enumerated().map { index, frame in
            FrameSummary(index: index, frame: frame, isBlamed: FirebaseEventFrames.isBlamed(frame, in: event))
        }
    }
}

public struct FrameSummary: Encodable, Sendable {
    public var index: Int
    public var binaryName: String
    public var symbol: String?
    public var file: String?
    public var line: Int?
    public var isBlamed: Bool

    public init(index: Int, frame: FirebaseFrame, isBlamed: Bool? = nil) {
        self.index = index
        self.binaryName = frame.library ?? "?"
        self.symbol = frame.symbol
        self.file = frame.file
        self.line = frame.line
        self.isBlamed = isBlamed ?? frame.blamed
    }
}
