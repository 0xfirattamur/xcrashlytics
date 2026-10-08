import Foundation
import Testing
@testable import xcrashlytics

/// Real-disk tests in a throwaway temp directory.
@Suite("DiskFileStore")
struct DiskFileStoreTests {
    private let fileStore = DiskFileStore()

    private func withTempDirectory(_ body: (String) throws -> Void) throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("xc-fileStore-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: raw, withIntermediateDirectories: true)
        // The enumerator reports canonical paths (/private/var/…), so compare against those.
        let directoryPath = realpath(raw, nil).map { String(cString: $0) } ?? raw
        defer {
            // Undo any chmod/chflags the test applied so cleanup succeeds.
            for path in [directoryPath, "\(directoryPath)/config.json"] {
                chflags(path, 0)
                chmod(path, 0o755)
            }
            try? FileManager.default.removeItem(atPath: directoryPath)
        }
        try body(directoryPath)
    }

    private func leftovers(in directoryPath: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directoryPath)) ?? []).filter { $0.contains(".tmp-") }
    }

    @Test("writeDataAtomically creates a new file and missing parent directories")
    func createsFileAndParents() throws {
        try withTempDirectory { directoryPath in
            let path = "\(directoryPath)/nested/deeper/config.json"
            try fileStore.writeDataAtomically(Data("one".utf8), to: path)
            #expect(try fileStore.readData(at: path) == Data("one".utf8))
            #expect(leftovers(in: "\(directoryPath)/nested/deeper").isEmpty)
        }
    }

    @Test("writeDataAtomically replaces an existing file and leaves no tmp file")
    func replacesExistingFile() throws {
        try withTempDirectory { directoryPath in
            let path = "\(directoryPath)/config.json"
            try fileStore.writeDataAtomically(Data("old".utf8), to: path)
            try fileStore.writeDataAtomically(Data("new".utf8), to: path)
            #expect(try fileStore.readData(at: path) == Data("new".utf8))
            #expect(leftovers(in: directoryPath).isEmpty)
        }
    }

    @Test("writeDataAtomically reports a replace failure and cleans up its tmp file")
    func replaceFailurePropagates() throws {
        try withTempDirectory { directoryPath in
            let path = "\(directoryPath)/config.json"
            try fileStore.writeDataAtomically(Data("old".utf8), to: path)
            #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)

            let error = #expect(throws: FileStoreError.self) {
                try fileStore.writeDataAtomically(Data("new".utf8), to: path)
            }

            #expect(error?.path == path)
            #expect(error?.localizedDescription.contains(".tmp-") == false)
            chflags(path, 0)
            #expect(try fileStore.readData(at: path) == Data("old".utf8))
            #expect(leftovers(in: directoryPath).isEmpty)
        }
    }

    @Test("writeDataAtomically into a read-only directory fails and leaves nothing behind")
    func readOnlyDirectoryFails() throws {
        try withTempDirectory { directoryPath in
            chmod(directoryPath, 0o555)
            let error = #expect(throws: FileStoreError.self) {
                try fileStore.writeDataAtomically(Data("x".utf8), to: "\(directoryPath)/config.json")
            }
            #expect(error?.localizedDescription.contains(".tmp-") == false)
            chmod(directoryPath, 0o755)
            #expect(leftovers(in: directoryPath).isEmpty)
            #expect(!fileStore.exists(at: "\(directoryPath)/config.json"))
        }
    }

    @Test("listFiles matches extensions case-insensitively, sorted, ignoring hidden files")
    func enumerateMatchesAndSorts() throws {
        try withTempDirectory { directoryPath in
            for name in ["b/B.PLIST", "a/A.plist", "a/skip.txt", ".hidden/H.plist"] {
                try fileStore.writeDataAtomically(Data(), to: "\(directoryPath)/\(name)")
            }
            #expect(try fileStore.listFiles(under: directoryPath, withExtensions: ["plist"]) == ["\(directoryPath)/a/A.plist", "\(directoryPath)/b/B.PLIST"])
        }
    }

    @Test("listFiles prunes skipped directories at any depth but never the root")
    func enumeratePrunes() throws {
        try withTempDirectory { directoryPath in
            let root = "\(directoryPath)/build"
            for name in ["App/g.plist", "Pods/Vendor/g.plist", "node_modules/x/y/g.plist", "App/Pods/g.plist", "ok/g.plist"] {
                try fileStore.writeDataAtomically(Data(), to: "\(root)/\(name)")
            }
            let found = try fileStore.listFiles(
                under: root, withExtensions: ["plist"], skippingDirectories: ["Pods", "node_modules", "build"])
            #expect(found == ["\(root)/App/g.plist", "\(root)/ok/g.plist"])
        }
    }

    @Test("listFiles of a missing directory is empty")
    func missingPaths() throws {
        try withTempDirectory { directoryPath in
            let found = try fileStore.listFiles(under: "\(directoryPath)/nope", withExtensions: ["x"])
            #expect(found.isEmpty)
        }
    }

    @Test("attributes reports size")
    func attributesAndDelete() throws {
        try withTempDirectory { directoryPath in
            let path = "\(directoryPath)/f.txt"
            try fileStore.writeDataAtomically(Data("abcd".utf8), to: path)
            #expect(try fileStore.attributes(at: path).size == 4)
        }
    }
}
