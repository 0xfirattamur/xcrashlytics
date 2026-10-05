//
//  InMemoryFileSystem.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
@testable import xcrashlytics

/// In-RAM `FileSystem` impl used in tests.
///
/// State is a flat `[path: Entry]` dict, so "directories" are implicit — any
/// path matching a prefix is considered to be inside that directory. `seed(_:)`
/// helpers let a test set up fixture files without touching the real disk.
///
/// `@unchecked Sendable` because state is mutable but tests serialize access.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    /// One file stored in memory.
    struct Entry {
        var data: Data
        var mtime: Date
    }

    private var files: [String: Entry] = [:]
    private var directories: Set<String> = []

    init() {}

    func fileExists(at path: String) -> Bool { files[path] != nil }

    func read(at path: String) throws -> Data {
        guard let e = files[path] else {
            throw NSError(
                domain: "InMemoryFileSystem",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no such file: \(path)"]
            )
        }
        return e.data
    }

    func write(_ data: Data, to path: String) throws {
        files[path] = Entry(data: data, mtime: Date())
    }

    func atomicWrite(_ data: Data, to path: String) throws {
        let tmp = "\(path).tmp-\(UUID().uuidString)"
        files[tmp] = Entry(data: data, mtime: Date())
        files[path] = files[tmp]
        files.removeValue(forKey: tmp)
    }

    func enumerate(at path: String, matchingExtensions extensions: Set<String>) throws -> [String] {
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
            throw NSError(domain: "InMemoryFileSystem", code: 2)
        }
        return FileAttributes(size: e.data.count, modificationDate: e.mtime)
    }

    func createDirectory(at path: String) throws {
        directories.insert(path)
    }

    func delete(at path: String) throws {
        files.removeValue(forKey: path)
    }

    // MARK: - Test helpers

    /// Seeds a file with raw `Data`.
    func seed(_ path: String, data: Data, mtime: Date = Date()) {
        files[path] = Entry(data: data, mtime: mtime)
    }

    /// Seeds a file from a UTF-8 string — convenience for text fixtures.
    func seed(_ path: String, text: String, mtime: Date = Date()) {
        files[path] = Entry(data: Data(text.utf8), mtime: mtime)
    }

    /// All seeded/written paths, sorted — useful for assertions like "no tmp file left behind".
    func snapshotPaths() -> [String] { Array(files.keys).sorted() }
}
