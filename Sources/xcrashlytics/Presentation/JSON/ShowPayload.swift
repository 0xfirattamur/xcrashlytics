import Foundation

struct ShowPayload: Encodable {
    var event: CrashEventPayload
    var issue: CrashIssue?
    var activity: ActivityPayload?
    var detail: EventDetailPayload?
    var exceptionSummary: EventDetailPayload.ExceptionSummary?
    var attribution: LibraryAttributionPayload?
    var frameNote: FrameFilterNote?
    var versionRange: VersionRangePayload?
    var runtime: EventRuntimePayload?

    init(_ detail: CrashDetail, includeBreadcrumbs: Bool) {
        // The selected event, else the newest sampled one the overview's stack comes from.
        let sourceEvent = detail.firebaseEvent ?? detail.latestEvent
        let view = sourceEvent.map { EventDetailView($0, includeBreadcrumbs: includeBreadcrumbs) }
        let attribution = LibraryAttributionBuilder(selector: detail.frameSelector)
            .attribution(for: detail.sampledEvents)

        event = CrashEventPayload(detail.event)
        issue = detail.issue
        activity = detail.activity.map(ActivityPayload.init)
        self.detail = view.map { EventDetailPayload($0, includesException: false) }
        exceptionSummary = view?.exception.map { .init(type: $0.type, message: $0.message) }
        self.attribution = attribution.map(LibraryAttributionPayload.init)
        frameNote = Self.frameNote(for: detail, sourceEvent: sourceEvent)
        versionRange = detail.versionRange.map(VersionRangePayload.init)
        runtime = detail.firebaseEvent.map(EventRuntimePayload.init)
    }

    private static func frameNote(for detail: CrashDetail, sourceEvent: CrashlyticsEvent?) -> FrameFilterNote? {
        guard let sourceEvent else { return nil }
        return FrameFilterNote.ifEmpty(
            sourceEvent,
            filter: detail.frameFilter,
            selector: detail.frameSelector,
            shownFrameCount: detail.event.frames.count)
    }

    private enum CodingKeys: String, CodingKey {
        case eventsCount, impactedUsersCount, firstSeenVersion, lastSeenVersion, activity, errorType, state
        case exception, dominantLibraries, blameLibraries, noFramesReason, appFramesAbsent, crashedLibrary
        case versionRange
    }

    func encode(to encoder: Encoder) throws {
        try event.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(issue?.eventsCount, forKey: .eventsCount)
        try container.encodeIfPresent(issue?.impactedUsersCount, forKey: .impactedUsersCount)
        try container.encodeIfPresent(issue?.firstSeenVersion, forKey: .firstSeenVersion)
        try container.encodeIfPresent(issue?.lastSeenVersion, forKey: .lastSeenVersion)
        try container.encodeIfPresent(versionRange, forKey: .versionRange)
        try container.encodeIfPresent(issue?.errorType, forKey: .errorType)
        try container.encodeIfPresent(issue?.state, forKey: .state)
        try container.encodeIfPresent(activity, forKey: .activity)
        try detail?.encode(to: encoder)
        if let exceptionSummary {
            try container.encode(
                ExceptionPayload(descriptor: event.exception, summary: exceptionSummary), forKey: .exception)
        }
        try container.encodeIfPresent(attribution?.dominantLibraries, forKey: .dominantLibraries)
        try container.encodeIfPresent(attribution?.blameLibraries, forKey: .blameLibraries)
        try container.encodeIfPresent(frameNote?.reason, forKey: .noFramesReason)
        try container.encodeIfPresent(frameNote?.appFramesAbsent == true ? true : nil, forKey: .appFramesAbsent)
        try container.encodeIfPresent(frameNote?.crashedLibrary, forKey: .crashedLibrary)
        try runtime?.encode(to: encoder)
    }
}

private struct ExceptionPayload: Encodable {
    let descriptor: ExceptionDescriptorPayload
    let summary: EventDetailPayload.ExceptionSummary

    enum CodingKeys: String, CodingKey {
        case exceptionType, signal, subtype, description, type, message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(descriptor.exceptionType, forKey: .exceptionType)
        try container.encodeIfPresent(descriptor.signal, forKey: .signal)
        try container.encodeIfPresent(descriptor.subtype, forKey: .subtype)
        try container.encodeIfPresent(descriptor.description, forKey: .description)
        try container.encodeIfPresent(summary.type, forKey: .type)
        try container.encodeIfPresent(summary.message, forKey: .message)
    }
}
