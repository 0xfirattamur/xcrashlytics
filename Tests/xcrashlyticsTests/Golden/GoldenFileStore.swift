import Foundation
@testable import xcrashlytics

/// The in-memory store with injectable faults, for failures an in-memory store never has by itself.
final class GoldenFileStore: FileStore, @unchecked Sendable {
    enum Fault {
        case none
        /// Reading `.xcrashlytics.json` throws.
        case unreadableConfig
        /// Listing `GoldenWorld.crashDirectory` throws.
        case unscannableCrashDirectory
        /// Every write throws.
        case readOnly
    }

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "injected file system fault" }
    }

    let base: InMemoryFileStore
    private let fault: Fault
    private let configPath: String

    init(base: InMemoryFileStore, fault: Fault, configPath: String) {
        self.base = base
        self.fault = fault
        self.configPath = configPath
    }

    func exists(at path: String) -> Bool { base.exists(at: path) }

    func readData(at path: String) throws -> Data {
        if fault == .unreadableConfig, path == configPath { throw Failure() }
        return try base.readData(at: path)
    }

    func writeDataAtomically(_ data: Data, to path: String) throws {
        if fault == .readOnly { throw Failure() }
        try base.writeDataAtomically(data, to: path)
    }

    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] {
        if fault == .unscannableCrashDirectory, path == GoldenWorld.crashDirectory { throw Failure() }
        return try base.listFiles(under: path, withExtensions: extensions)
    }

    func attributes(at path: String) throws -> FileAttributes { try base.attributes(at: path) }
}
