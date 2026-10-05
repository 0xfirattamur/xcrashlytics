//
//  Clock.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Time abstraction so tests can use a `FixedClock` and avoid wall-clock flakiness.
protocol Clock: Sendable {
    /// Returns "now".
    func now() -> Date
}

/// Production `Clock` impl backed by the system wall clock.
struct SystemClock: Clock {
    func now() -> Date { Date() }
}
