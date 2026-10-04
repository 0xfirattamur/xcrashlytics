//
//  XcodeCrash.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// A `CrashEvent` parsed from a local Xcode crash file, paired with its file
/// metadata (path, mtime, size). `event.id` is the canonical `XC-` id.
public struct XcodeCrash: Codable, Sendable, Hashable {
    /// The parsed crash event.
    public var event: CrashEvent
    /// Absolute path to the source `.crash` file.
    public var filePath: String
    /// File modification time — used to sort recent crashes first.
    public var fileMtime: Date
    /// File size in bytes.
    public var fileSize: Int

    public init(event: CrashEvent, filePath: String, fileMtime: Date, fileSize: Int) {
        self.event = event
        self.filePath = filePath
        self.fileMtime = fileMtime
        self.fileSize = fileSize
    }
}
