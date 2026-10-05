//
//  FileSystem.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Minimal file metadata returned by `FileSystem.attributes`.
struct FileAttributes: Sendable, Hashable {
    /// Size in bytes.
    var size: Int
    /// Last-modified timestamp.
    var modificationDate: Date

}

/// Abstraction over filesystem reads/writes/enumeration.
///
/// Hidden behind a protocol so tests can swap in `InMemoryFileSystem` and avoid
/// touching the real disk. Production code uses `DiskFileSystem`.
protocol FileSystem: Sendable {
    /// Returns `true` if a regular file exists at `path`.
    func fileExists(at path: String) -> Bool
    /// Reads the file's contents.
    func read(at path: String) throws -> Data
    /// Overwrites the file with `data`. Non-atomic.
    func write(_ data: Data, to path: String) throws
    /// Writes `data` atomically via tempfile + rename — readers see either old
    /// contents or new contents, never a half-written file.
    func atomicWrite(_ data: Data, to path: String) throws
    /// Recursively lists files under `path` whose extension is in `extensions`.
    /// Result is sorted for deterministic ordering.
    func enumerate(at path: String, matchingExtensions extensions: Set<String>) throws -> [String]
    /// Returns size + mtime for the file at `path`.
    func attributes(at path: String) throws -> FileAttributes
    /// Creates the directory (and any missing parents). Idempotent.
    func createDirectory(at path: String) throws
    /// Deletes the file if it exists; no-op otherwise.
    func delete(at path: String) throws
}

/// Production `FileSystem` impl backed by `FileManager`.
struct DiskFileSystem: FileSystem {
    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func read(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func write(_ data: Data, to path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    func atomicWrite(_ data: Data, to path: String) throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try createDirectoryIfNeeded(dir.path)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        if fm.fileExists(atPath: url.path) {
            _ = try? fm.replaceItemAt(url, withItemAt: tmp)
            if fm.fileExists(atPath: tmp.path) {
                try? fm.removeItem(at: tmp)
            }
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    func enumerate(at path: String, matchingExtensions extensions: Set<String>) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let it = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [String] = []
        for case let item as URL in it {
            let ext = item.pathExtension.lowercased()
            if extensions.contains(ext) {
                out.append(item.path)
            }
        }
        out.sort()
        return out
    }

    func attributes(at path: String) throws -> FileAttributes {
        let raw = try FileManager.default.attributesOfItem(atPath: path)
        let size = (raw[.size] as? Int) ?? 0
        let mtime = (raw[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return FileAttributes(size: size, modificationDate: mtime)
    }

    func createDirectory(at path: String) throws {
        try createDirectoryIfNeeded(path)
    }

    func delete(at path: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    private func createDirectoryIfNeeded(_ path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue { return }
        }
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}
