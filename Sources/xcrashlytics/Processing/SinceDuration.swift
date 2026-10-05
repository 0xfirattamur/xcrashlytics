//
//  SinceDuration.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

enum SinceDurationError: Error, Equatable, LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(value):
            "invalid --since '\(value)' — use 7d, 24h, 30m, or all."
        }
    }
}

/// Parses relative durations like "7d", "24h", "30m" into an absolute cutoff.
/// "all" and "none" mean no cutoff.
enum SinceDuration {
    static func cutoffDate(from value: String, now: Date) throws -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "all" || trimmed == "none" { return nil }
        guard let unit = trimmed.last, let amount = Double(trimmed.dropLast()) else {
            throw SinceDurationError.invalid(value)
        }
        let seconds: TimeInterval
        switch unit {
        case "d":
            seconds = amount * 86_400
        case "h":
            seconds = amount * 3_600
        case "m":
            seconds = amount * 60
        default:
            throw SinceDurationError.invalid(value)
        }
        return now.addingTimeInterval(-seconds)
    }
}
