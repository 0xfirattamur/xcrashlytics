import Foundation
@testable import xcrashlytics

/// In-RAM `FileStore` impl used in tests.
///
/// State is a flat `[path: Entry]` dict, so "directories" are implicit — any
/// path matching a prefix is considered to be inside that directory. `seed(_:)`
/// helpers let a test set up fixture files without touching the real disk.
///
/// `@unchecked Sendable` because state is mutable but tests serialize access.
final class InMemoryFileStore: FileStore, @unchecked Sendable {
    /// One file stored in memory.
    struct Entry {
        var data: Data
        var modificationDate: Date
    }

    private var files: [String: Entry] = [:]

    init() {}

    func exists(at path: String) -> Bool { files[path] != nil }

    func readData(at path: String) throws -> Data {
        guard let e = files[path] else {
            throw NSError(
                domain: "InMemoryFileStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no such file: \(path)"]
            )
        }
        return e.data
    }

    func writeDataAtomically(_ data: Data, to path: String) throws {
        files[path] = Entry(data: data, modificationDate: Date())
    }

    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let matched = files.keys.filter { key in
            guard key.hasPrefix(prefix) else { return false }
            let ext = (key as NSString).pathExtension.lowercased()
            return extensions.contains(ext)
        }
        return matched.sorted()
    }

    func attributes(at path: String) throws -> FileAttributes {
        guard let e = files[path] else {
            throw NSError(domain: "InMemoryFileStore", code: 2)
        }
        return FileAttributes(size: e.data.count, modificationDate: e.modificationDate)
    }

    // MARK: - Test helpers

    /// Seeds a file with raw `Data`.
    func seed(_ path: String, data: Data, modificationDate: Date = Date()) {
        files[path] = Entry(data: data, modificationDate: modificationDate)
    }

    /// Seeds a file from a UTF-8 string — convenience for text fixtures.
    func seed(_ path: String, text: String, modificationDate: Date = Date()) {
        files[path] = Entry(data: Data(text.utf8), modificationDate: modificationDate)
    }

    /// All seeded/written paths, sorted.
    func snapshotPaths() -> [String] { Array(files.keys).sorted() }
}

extension FileStore {
    /// Fallback for fakes that only implement the plain listing; `DiskFileStore` has its own.
    func listFiles(
        under path: String,
        withExtensions extensions: Set<String>,
        skippingDirectories skippedDirectories: Set<String>
    ) throws -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return try listFiles(under: path, withExtensions: extensions).filter { file in
            let directories = file.hasPrefix(prefix) ? file.dropFirst(prefix.count).split(separator: "/").dropLast() : []
            return !directories.contains { skippedDirectories.contains(String($0)) }
        }
    }
}
