import Foundation

enum CrashlyticsEventMapper {
    // Crashlytics quirk: fatal events often carry no exception type, so `fallbackException` applies.
    static func crashEvent(
        from event: CrashlyticsEvent,
        canonicalId: String,
        fallbackException: ExceptionDescriptor? = nil,
        frameFilter: FrameFilter = .none,
        frameSelector: FrameSelector
    ) -> CrashEvent {
        let frames = frameSelector.frames(from: event, filter: frameFilter)
        let timestamp = event.eventTime.flatMap(EventTimestampParser.parse)
        return CrashEvent(
            id: canonicalId,
            providerId: event.eventId,
            source: .firebase,
            bundleId: event.bundleOrPackage,
            bundleVersion: event.displayVersion,
            osVersion: event.osVersion,
            deviceModel: event.deviceModel,
            crashedThreadIndex: frameSelector.chosenThreadIndex(in: event) ?? 0,
            exception: event.exceptions.first?.type.map { ExceptionDescriptor(exceptionType: $0) }
                ?? fallbackException
                ?? ExceptionDescriptor(exceptionType: "FIREBASE_EVENT"),
            frames: frames,
            timestamp: timestamp
        )
    }
}
