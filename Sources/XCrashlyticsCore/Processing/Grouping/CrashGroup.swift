//
//  CrashGroup.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// A cluster of same-culprit crashes — Firebase issues and local Xcode crashes
/// that share a `CrashSignature`. Collapses Firebase's over-splitting (one
/// function reported as several issues) and links it to local repros.
public struct CrashGroup: Sendable, Equatable {
    /// Normalized culprit symbol — the group key.
    public let symbol: String
    /// Owning module/binary, for display.
    public let module: String?
    public let firebase: [CrashIssue]
    public let xcode: [XcodeCrash]

    public init(symbol: String, module: String?, firebase: [CrashIssue], xcode: [XcodeCrash]) {
        self.symbol = symbol
        self.module = module
        self.firebase = firebase
        self.xcode = xcode
    }

    /// Total Firebase events across the group's issues.
    public var totalEvents: Int { firebase.compactMap(\.eventsCount).reduce(0, +) }
    /// Total impacted users across the group's issues.
    public var totalUsers: Int { firebase.compactMap(\.impactedUsersCount).reduce(0, +) }
    /// True when the group has both a Firebase issue and a local crash — i.e. a
    /// local repro of a production issue.
    public var isCrossSource: Bool { !firebase.isEmpty && !xcode.isEmpty }
}
