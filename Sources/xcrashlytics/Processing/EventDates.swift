//
//  EventDates.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

/// Date handling for Firebase event timestamps.
enum EventDates {
    static func parse(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(value, strategy: Date.ISO8601FormatStyle())
    }

    /// "2026-06-10" UTC day bucket, or nil when the timestamp is absent/unparseable.
    static func dayString(from value: String?) -> String? {
        guard let value, let date = parse(value) else { return nil }
        return date.formatted(Date.ISO8601FormatStyle().year().month().day())
    }

    /// Whether an event falls on or after the cutoff. No cutoff admits everything;
    /// an unparseable timestamp is excluded.
    static func isIncluded(event: FirebaseEvent, onOrAfter cutoff: Date?) -> Bool {
        guard let cutoff else { return true }
        guard let eventTime = event.eventTime, let date = parse(eventTime) else { return false }
        return date >= cutoff
    }
}
