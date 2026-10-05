//
//  Sleeper.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Async delay abstraction so backoff loops can be exercised in tests without
/// actually waiting.
protocol Sleeper: Sendable {
    /// Suspends for the given duration.
    func sleep(seconds: Double) async throws
}

/// Production `Sleeper` impl backed by `Task.sleep`.
struct TaskSleeper: Sleeper {
    func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
