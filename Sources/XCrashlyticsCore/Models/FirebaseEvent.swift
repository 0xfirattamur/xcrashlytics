//
//  FirebaseEvent.swift
//  xcrashlytics
//

import Foundation

/// One Crashlytics event as the rest of the app sees it. Decoding and wire
/// quirks (string-typed numbers, issue-as-string, nested version objects)
/// stay in `FirebaseDTO`; this is the flattened domain shape.
public struct FirebaseEvent: Sendable, Equatable {
    /// Firebase event id (the last path segment of the resource name).
    public var eventId: String?
    public var issueId: String?
    public var issueTitle: String?
    public var issueSubtitle: String?
    /// RFC 3339 event time as reported by Firebase.
    public var eventTime: String?
    public var platform: String?
    public var bundleOrPackage: String?
    public var processState: String?
    public var displayVersion: String?
    public var buildVersion: String?
    public var deviceModel: String?
    public var deviceOrientation: String?
    public var osVersion: String?
    public var osOrientation: String?
    public var jailbroken: Bool?
    public var memoryFree: Int?
    public var memoryUsed: Int?
    public var storageFree: Int?
    public var storageUsed: Int?
    public var userId: String?
    public var blameFrame: FirebaseFrame?
    public var exceptions: [FirebaseException]
    public var threads: [FirebaseThread]
    /// The event's raw JSON object, kept for fields not promoted to properties.
    public var rawJSON: String?

    public init(
        eventId: String? = nil,
        issueId: String? = nil,
        issueTitle: String? = nil,
        issueSubtitle: String? = nil,
        eventTime: String? = nil,
        platform: String? = nil,
        bundleOrPackage: String? = nil,
        processState: String? = nil,
        displayVersion: String? = nil,
        buildVersion: String? = nil,
        deviceModel: String? = nil,
        deviceOrientation: String? = nil,
        osVersion: String? = nil,
        osOrientation: String? = nil,
        jailbroken: Bool? = nil,
        memoryFree: Int? = nil,
        memoryUsed: Int? = nil,
        storageFree: Int? = nil,
        storageUsed: Int? = nil,
        userId: String? = nil,
        blameFrame: FirebaseFrame? = nil,
        exceptions: [FirebaseException] = [],
        threads: [FirebaseThread] = [],
        rawJSON: String? = nil
    ) {
        self.eventId = eventId
        self.issueId = issueId
        self.issueTitle = issueTitle
        self.issueSubtitle = issueSubtitle
        self.eventTime = eventTime
        self.platform = platform
        self.bundleOrPackage = bundleOrPackage
        self.processState = processState
        self.displayVersion = displayVersion
        self.buildVersion = buildVersion
        self.deviceModel = deviceModel
        self.deviceOrientation = deviceOrientation
        self.osVersion = osVersion
        self.osOrientation = osOrientation
        self.jailbroken = jailbroken
        self.memoryFree = memoryFree
        self.memoryUsed = memoryUsed
        self.storageFree = storageFree
        self.storageUsed = storageUsed
        self.userId = userId
        self.blameFrame = blameFrame
        self.exceptions = exceptions
        self.threads = threads
        self.rawJSON = rawJSON
    }
}

extension FirebaseEvent {
    /// Crashed thread, else first thread, else first exception, else the
    /// blame frame — mapped to `Frame`, with no app/system filtering.
    public func representativeFrames() -> [Frame] {
        let chosen = threads.first(where: \.crashed)?.frames.nilIfEmpty
            ?? threads.first?.frames.nilIfEmpty
            ?? exceptions.first?.frames.nilIfEmpty
            ?? blameFrame.map { [$0] }
            ?? []
        return chosen.enumerated().map { idx, f in
            Frame(
                index: idx, binaryName: f.library ?? "?", symbol: f.symbol,
                file: f.file, line: f.line, column: nil, address: nil,
                imageUUID: nil, isSymbolicated: f.symbol != nil)
        }
    }
}

public struct FirebaseThread: Sendable, Equatable {
    public var name: String?
    public var title: String?
    public var crashed: Bool
    public var frames: [FirebaseFrame]

    public init(name: String? = nil, title: String? = nil, crashed: Bool = false, frames: [FirebaseFrame] = []) {
        self.name = name
        self.title = title
        self.crashed = crashed
        self.frames = frames
    }
}

public struct FirebaseException: Sendable, Equatable {
    public var type: String?
    public var exceptionMessage: String?
    public var title: String?
    public var subtitle: String?
    public var blamed: Bool
    public var frames: [FirebaseFrame]

    public init(
        type: String? = nil,
        exceptionMessage: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        blamed: Bool = false,
        frames: [FirebaseFrame] = []
    ) {
        self.type = type
        self.exceptionMessage = exceptionMessage
        self.title = title
        self.subtitle = subtitle
        self.blamed = blamed
        self.frames = frames
    }
}

public struct FirebaseFrame: Sendable, Equatable {
    public var symbol: String?
    public var file: String?
    public var line: Int?
    public var library: String?
    public var owner: String?
    public var blamed: Bool
    public var offset: String?

    public init(
        symbol: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        library: String? = nil,
        owner: String? = nil,
        blamed: Bool = false,
        offset: String? = nil
    ) {
        self.symbol = symbol
        self.file = file
        self.line = line
        self.library = library
        self.owner = owner
        self.blamed = blamed
        self.offset = offset
    }
}
