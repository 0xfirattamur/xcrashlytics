//
//  XcodeCrashScanner.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Walks one or more directories looking for crash files.
struct XcodeCrashScanner: Sendable {
    private let fs: FileSystem
    /// Organizer xccrashpoints store crashes as legacy-format `.crash` logs.
    private static let supportedExtensions: Set<String> = ["crash"]

    init(fs: FileSystem) {
        self.fs = fs
    }

    /// Returns paths to every `.crash` file found under the given directories,
    /// sorted for determinism, plus a warning per directory that exists but
    /// failed to enumerate. Missing directories are skipped silently because
    /// `FileSystem.enumerate` returns an empty list for nonexistent paths.
    func scan(directories: [String]) -> (paths: [String], warnings: [CrashLoadWarning]) {
        var paths: [String] = []
        var warnings: [CrashLoadWarning] = []
        for dir in directories {
            do {
                paths.append(contentsOf: try fs.enumerate(at: dir, matchingExtensions: Self.supportedExtensions))
            } catch {
                warnings.append(CrashLoadWarning(
                    code: "XCODE_SCAN_FAILED", message: "failed to scan \(dir): \(error)", path: dir))
            }
        }
        return (paths.sorted(), warnings)
    }
}
