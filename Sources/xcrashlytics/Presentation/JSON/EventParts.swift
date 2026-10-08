import Foundation

// Building blocks `events` and `show` compose into their payloads. Parents encode them
// flat into one object (`try part.encode(to: encoder)`), so every key lands at the top level.

struct EventHeaderPayload: Encodable, Sendable {
    var id: String
    var firebaseEventId: String
    var issueId: String
    var eventTime: String?

    init(_ event: CrashlyticsEvent, issueId: String) {
        id = CrashlyticsIdFormatter.canonicalEventId(event, issueId: issueId)
        firebaseEventId = event.eventId ?? "unknown"
        self.issueId = CrashlyticsIdFormatter.canonicalIssueId(issueId)
        eventTime = event.eventTime
    }
}

struct EventEnvironmentPayload: Encodable, Sendable {
    var appVersion: String?
    var deviceModel: String?
    var osVersion: String?

    init(_ event: CrashlyticsEvent) {
        appVersion = event.displayVersion
        deviceModel = event.deviceModel
        osVersion = event.osVersion
    }
}

struct EventRuntimePayload: Encodable, Sendable {
    var appBuild: String?
    var processState: String?
    var deviceOrientation: String?
    var osOrientation: String?
    var isJailbroken: Bool?
    var memoryFreeBytes: Int?
    var memoryUsedBytes: Int?
    var storageFreeBytes: Int?
    var storageUsedBytes: Int?
    var userIdHash: String?

    init(_ event: CrashlyticsEvent) {
        appBuild = event.buildVersion
        processState = event.processState
        deviceOrientation = event.deviceOrientation
        osOrientation = event.osOrientation
        isJailbroken = event.jailbroken
        memoryFreeBytes = event.memoryFree
        memoryUsedBytes = event.memoryUsed
        storageFreeBytes = event.storageFree
        storageUsedBytes = event.storageUsed
        userIdHash = event.userId.map(SHA256Hasher.hexDigest(of:))
    }
}

struct EventFramesPayload: Encodable, Sendable {
    var frames: [FrameSummary]
    var noFramesReason: String?
    var appFramesAbsent: Bool?
    var crashedLibrary: String?

    init(_ event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector) {
        frames = FrameSummary.frames(of: event, filter: filter, selector: selector)
        let note = FrameFilterNote.ifEmpty(
            event, filter: filter, selector: selector, shownFrameCount: frames.count)
        noFramesReason = note?.reason
        appFramesAbsent = note?.appFramesAbsent == true ? true : nil
        crashedLibrary = note?.crashedLibrary
    }
}

// Privacy: user ids are redacted before they reach this payload.
struct EventDetailPayload: Encodable, Sendable {
    var crashInfo: [String]?
    /// The line(s) of `crashInfo` naming the failure; for an NSException crash without
    /// crash info, `<type>: <message>`.
    var crashMessage: String?
    var exception: ExceptionSummary?
    var customKeys: [String: String]?
    var logs: [Log]?
    var crashedThread: CrashedThread?
    var breadcrumbs: [Breadcrumb]?

    struct ExceptionSummary: Encodable, Sendable {
        var type: String?
        var message: String?
    }

    struct Log: Encodable, Sendable {
        var time: String?
        var message: String?
    }

    struct CrashedThread: Encodable, Sendable {
        var title: String?
        var signal: String?
        var signalCode: String?
        var crashAddress: String?
        var queue: String?
    }

    struct Breadcrumb: Encodable, Sendable {
        var time: String?
        var title: String?
        var params: [String: String]?
    }

    /// `compact` keeps only what identifies the failure; `show` merges the exception into its own object.
    init(_ view: EventDetailView, compact: Bool = false, includesException: Bool = true) {
        crashInfo = view.crashInfo
        crashMessage = view.crashMessage
        exception = includesException
            ? view.exception.map { ExceptionSummary(type: $0.type, message: $0.message) }
            : nil
        crashedThread = view.crashedThread.map {
            CrashedThread(
                title: $0.title, signal: $0.signal, signalCode: $0.signalCode,
                crashAddress: $0.crashAddress, queue: $0.queue)
        }
        guard !compact else { return }
        customKeys = view.customKeys
        logs = view.logs?.map { Log(time: $0.time, message: $0.message) }
        breadcrumbs = view.breadcrumbs?.map { Breadcrumb(time: $0.time, title: $0.title, params: $0.params) }
    }
}
