//
//  MockProcessRunner.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
@testable import xcrashlytics

/// Scripted `ProcessRunner` for tests.
///
/// Test sets up a closure that maps `(executable, arguments)` to a
/// `ProcessResult`. Default behavior is to throw — forces every test path to
/// be explicit about what subprocess calls it expects.
final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    /// `(executable, arguments) -> ProcessResult` lookup. Return `nil` to
    /// fall back to the throw-on-miss default.
    var handler: ((String, [String]) -> ProcessResult?)?
    /// History of every invocation — useful for asserting "was atos called".
    private(set) var calls: [(String, [String])] = []

    init(handler: ((String, [String]) -> ProcessResult?)? = nil) {
        self.handler = handler
    }

    func run(executable: String, arguments: [String], stdin: String?) throws -> ProcessResult {
        calls.append((executable, arguments))
        if let result = handler?(executable, arguments) {
            return result
        }
        throw NSError(
            domain: "MockProcessRunner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no handler for \(executable) \(arguments)"]
        )
    }
}
