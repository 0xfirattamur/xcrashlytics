//
//  CrashRecordErrors.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Errors raised while parsing a `.crash` file into a `CrashEvent`.
enum CrashParsingError: Error, Equatable, Sendable {
    /// First line / JSON header could not be decoded.
    case malformedHeader(String)
    /// Body section could not be decoded or is missing required fields.
    case malformedBody(String)
    /// File extension or layout is not a known crash format.
    case unsupportedFormat(String)
    /// Filesystem-level failure while reading the source file.
    case ioError(String)
}

/// Errors raised while resolving symbols via `atos` and dSYMs.
enum SymbolicationError: Error, Equatable, Sendable {
    /// `atos` exited non-zero — exit code + captured stderr included.
    case atosFailed(exitCode: Int32, stderr: String)
    /// No dSYM matching the given UUID was found on disk.
    case dSYMNotFound(uuid: String)
    /// Binary referenced by a frame could not be located on disk.
    case binaryNotFound(path: String)
}
