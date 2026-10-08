import Foundation

struct EventSummary: Encodable, Sendable {
    var header: EventHeaderPayload
    var environment: EventEnvironmentPayload
    var runtime: EventRuntimePayload
    var detail: EventDetailPayload
    var frames: EventFramesPayload

    init(
        _ event: CrashlyticsEvent, issueId: String, filter: FrameFilter, selector: FrameSelector,
        includeBreadcrumbs: Bool
    ) {
        header = EventHeaderPayload(event, issueId: issueId)
        environment = EventEnvironmentPayload(event)
        runtime = EventRuntimePayload(event)
        detail = EventDetailPayload(EventDetailView(event, includeBreadcrumbs: includeBreadcrumbs))
        frames = EventFramesPayload(event, filter: filter, selector: selector)
    }

    func encode(to encoder: Encoder) throws {
        try header.encode(to: encoder)
        try environment.encode(to: encoder)
        try runtime.encode(to: encoder)
        try detail.encode(to: encoder)
        try frames.encode(to: encoder)
    }
}

struct EventFramesOnlySummary: Encodable, Sendable {
    var header: EventHeaderPayload
    var detail: EventDetailPayload
    var blamedFrame: FrameSummary?
    var frames: EventFramesPayload

    init(_ event: CrashlyticsEvent, issueId: String, filter: FrameFilter, selector: FrameSelector) {
        header = EventHeaderPayload(event, issueId: issueId)
        detail = EventDetailPayload(EventDetailView(event), compact: true)
        frames = EventFramesPayload(event, filter: filter, selector: selector)
        blamedFrame = frames.frames.first(where: \.isBlamed) ?? frames.frames.first
            ?? FrameSummary.unfilteredBlamedFrame(of: event, filter: filter, selector: selector)
    }

    private enum CodingKeys: String, CodingKey { case blamedFrame }

    func encode(to encoder: Encoder) throws {
        try header.encode(to: encoder)
        try detail.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(blamedFrame, forKey: .blamedFrame)
        try frames.encode(to: encoder)
    }
}
