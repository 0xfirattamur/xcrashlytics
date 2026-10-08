import Foundation

struct DiskFileStore: FileStore {
    func exists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func readData(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func writeDataAtomically(_ data: Data, to path: String) throws {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        let directoryURL = url.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        do {
            try createDirectoryIfNeeded(directoryURL.path)
            try data.write(to: temporaryURL)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            throw FileStoreError(path: path, underlying: error)
        }
    }

    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] {
        try listFiles(under: path, withExtensions: extensions, skippingDirectories: [])
    }

    func listFiles(
        under path: String,
        withExtensions extensions: Set<String>,
        skippingDirectories skippedDirectories: Set<String>
    ) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return [] }
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: keys, options: options
        ) else { return [] }
        var files: [String] = []
        for case let item as URL in enumerator {
            if !skippedDirectories.isEmpty,
               skippedDirectories.contains(item.lastPathComponent),
               (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
                continue
            }
            if extensions.contains(item.pathExtension.lowercased()) {
                files.append(item.path)
            }
        }
        files.sort()
        return files
    }

    func attributes(at path: String) throws -> FileAttributes {
        let raw = try FileManager.default.attributesOfItem(atPath: path)
        let size = (raw[.size] as? Int) ?? 0
        let modificationDate = (raw[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return FileAttributes(size: size, modificationDate: modificationDate)
    }

    private func createDirectoryIfNeeded(_ path: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
        }
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}
