//
//  FirebaseEventCrashMapper.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

enum FirebaseEventCrashMapper {
    static func crashEvent(
        from event: FirebaseEvent,
        canonicalId: String,
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
            exception: ExceptionInfo(exceptionType: event.exceptions.first?.type ?? "FIREBASE_EVENT"),
            frames: frames,
            timestamp: timestamp
        )
    }
}
