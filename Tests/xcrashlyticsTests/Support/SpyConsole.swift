import Foundation
@testable import xcrashlytics

/// Console test double that records everything written.
final class SpyConsole: Console, @unchecked Sendable {
    private(set) var outputs: [String] = []
    private(set) var warnings: [String] = []
    private(set) var diagnosticWrites: [String] = []

    init() {}

    func writeOutput(_ text: String) { outputs.append(text) }
    func reportWarning(_ message: String) { warnings.append(message) }
    func writeDiagnostic(_ text: String) { diagnosticWrites.append(text) }
}
