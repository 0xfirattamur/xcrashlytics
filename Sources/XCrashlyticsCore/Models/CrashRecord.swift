//
//  CrashRecord.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// A single crash event from Firebase or a local Xcode report.
///
/// Issue aggregates belong to `CrashIssue`; this value contains only one
/// occurrence and its event-level metadata.
public struct CrashEvent: Codable, Sendable, Hashable {
    /// Canonical CLI id: `XC-<incident>` or `FB-<issue>/events/<event>`.
    public var id: String
    /// Raw source identifier (incident UUID or Firebase event id).
    public var providerId: String?
    public var source: CrashSource
    public var bundleId: String?
    public var bundleVersion: String?
    public var osVersion: String?
    public var deviceModel: String?
    public var crashedThreadIndex: Int
    public var exception: ExceptionInfo
    public var frames: [Frame]
    public var binaryImages: [BinaryImage]
    public var timestamp: Date?
    public var rawPath: String?

    public init(
        id: String,
        providerId: String? = nil,
        source: CrashSource,
        bundleId: String? = nil,
        bundleVersion: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        crashedThreadIndex: Int,
        exception: ExceptionInfo,
        frames: [Frame],
        binaryImages: [BinaryImage] = [],
        timestamp: Date? = nil,
        rawPath: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.source = source
        self.bundleId = bundleId
        self.bundleVersion = bundleVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.crashedThreadIndex = crashedThreadIndex
        self.exception = exception
        self.frames = frames
        self.binaryImages = binaryImages
        self.timestamp = timestamp
        self.rawPath = rawPath
    }
}

/// A Firebase Crashlytics issue aggregate.
public struct CrashIssue: Codable, Sendable, Hashable {
    /// Canonical CLI id: `FB-<issue>`.
    public var id: String
    /// Raw Firebase issue id, used for API calls.
    public var providerId: String
    public var source: CrashSource
    public var title: String?
    public var subtitle: String?
    public var exceptionType: String
    public var signal: String?
    public var eventsCount: Int?
    public var impactedUsersCount: Int?
    public var firstSeenVersion: String?
    public var lastSeenVersion: String?

    public init(
        providerId: String,
        source: CrashSource = .firebase,
        title: String? = nil,
        subtitle: String? = nil,
        exceptionType: String,
        signal: String? = nil,
        eventsCount: Int? = nil,
        impactedUsersCount: Int? = nil,
        firstSeenVersion: String? = nil,
        lastSeenVersion: String? = nil
    ) {
        self.id = FirebaseIdentifiers.canonicalIssueId(providerId)
        self.providerId = providerId
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.exceptionType = exceptionType
        self.signal = signal
        self.eventsCount = eventsCount
        self.impactedUsersCount = impactedUsersCount
        self.firstSeenVersion = firstSeenVersion
        self.lastSeenVersion = lastSeenVersion
    }

    /// Last-seen version, falling back to first-seen.
    public var bundleVersion: String? { lastSeenVersion ?? firstSeenVersion }

    /// Issue-level exception summary; title carries the culprit location.
    public var exception: ExceptionInfo {
        ExceptionInfo(exceptionType: exceptionType, signal: signal, subtype: subtitle, description: title)
    }
}
