import Foundation

enum FirebaseEventCrashMapper {
    /// `fallbackException` applies when the event carries no exception type,
    /// as Firebase fatal crash events often do.
    static func crashEvent(
        from event: FirebaseEvent,
        canonicalId: String,
        fallbackException: ExceptionInfo? = nil,
        frameOptions: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) -> CrashEvent {
        let frames = FirebaseEventFrames.frames(from: event, options: frameOptions)
        let timestamp = event.eventTime.flatMap(EventDates.parse)
        return CrashEvent(
            id: canonicalId,
            providerId: event.eventId,
            source: .firebase,
            bundleVersion: event.displayVersion,
            osVersion: event.osVersion,
            deviceModel: event.deviceModel,
            crashedThreadIndex: 0,
            exception: event.exceptions.first?.type.map { ExceptionInfo(exceptionType: $0) }
                ?? fallbackException
                ?? ExceptionInfo(exceptionType: "FIREBASE_EVENT"),
            frames: frames,
            timestamp: timestamp
        )
    }
}
