//
//  XcodeCrashLoaderTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import Testing
@testable import xcrashlytics

/// FileSystem whose enumerate always throws — simulates an unreadable directory.
private struct ThrowingFileSystem: FileSystem {
    struct Failure: Error {}
    func fileExists(at path: String) -> Bool { true }
    func read(at path: String) throws -> Data { throw Failure() }
    func write(_ data: Data, to path: String) throws { throw Failure() }
    func atomicWrite(_ data: Data, to path: String) throws { throw Failure() }
    func enumerate(at path: String, matchingExtensions extensions: Set<String>) throws -> [String] { throw Failure() }
    func attributes(at path: String) throws -> FileAttributes { throw Failure() }
    func createDirectory(at path: String) throws { throw Failure() }
    func delete(at path: String) throws { throw Failure() }
}

@Suite("XcodeCrashLoader")
struct XcodeCrashLoaderTests {
    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("loads .crash files newest-first, surfaces malformed as warning, ignores other files")
    func loadsCrashDirectory() throws {
        let fs = InMemoryFileSystem()
        let dir = "/crashes"
        fs.seed(
            "\(dir)/A-good.crash",
            text: try loadFixture("sample.crash"),
            mtime: Date(timeIntervalSince1970: 2_000)
        )
        fs.seed(
            "\(dir)/B-good.crash",
            text: try loadFixture("sample-symbolicated.crash")
                .replacingOccurrences(
                    of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                    with: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                ),
            mtime: Date(timeIntervalSince1970: 1_000)
        )
        fs.seed(
            "\(dir)/C-bad.crash",
            text: try loadFixture("malformed.crash"),
            mtime: Date(timeIntervalSince1970: 3_000)
        )
        // Organizer stores other log kinds next to crashes — not scanned.
        fs.seed("\(dir)/D.xclaunchlog", text: "not a crash")

        let loader = XcodeCrashLoader(fs: fs)
        let result = loader.load(directories: [dir])

        #expect(result.crashes.count == 2)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.code == "XCODE_PARSE_FAILED")
        #expect(result.warnings.first?.path == "\(dir)/C-bad.crash")

        // newest first by mtime — A is mtime=2000, B is mtime=1000
        #expect(result.crashes[0].filePath.hasSuffix("A-good.crash"))
        #expect(result.crashes[1].filePath.hasSuffix("B-good.crash"))
    }

    @Test("missing directory is silently skipped")
    func missingDirectory() {
        let fs = InMemoryFileSystem()
        let loader = XcodeCrashLoader(fs: fs)
        let result = loader.load(directories: ["/does/not/exist"])
        #expect(result.crashes.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("unreadable directory surfaces as a warning, not a crash or silence")
    func warnsOnUnreadableDirectory() {
        let loader = XcodeCrashLoader(fs: ThrowingFileSystem())
        let result = loader.load(directories: ["/some/dir"])
        #expect(result.crashes.isEmpty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].code == "XCODE_SCAN_FAILED")
        #expect(result.warnings[0].path == "/some/dir")
    }

    @Test("duplicate incident keeps the source-located copy even when the raw twin is newer")
    func dedupesPreferringSourceLocatedCopy() throws {
        let fs = InMemoryFileSystem()
        let dir = "/crashes"
        // Raw twin (no source locations) is NEWER — must still lose.
        fs.seed(
            "\(dir)/raw.crash",
            text: try loadFixture("sample.crash"),
            mtime: Date(timeIntervalSince1970: 2_000)
        )
        fs.seed(
            "\(dir)/symbolicated.crash",
            text: try loadFixture("sample-symbolicated.crash"),
            mtime: Date(timeIntervalSince1970: 1_000)
        )

        let result = XcodeCrashLoader(fs: fs).load(directories: [dir])

        #expect(result.crashes.count == 1)
        #expect(result.crashes[0].filePath.hasSuffix("symbolicated.crash"))
        #expect(result.crashes[0].event.frames.contains { $0.file != nil })
    }

    @Test("duplicate incident with equally useful copies keeps the newest")
    func dedupesEqualCopiesByMtime() throws {
        let fs = InMemoryFileSystem()
        let dir = "/crashes"
        fs.seed("\(dir)/old.crash", text: try loadFixture("sample.crash"), mtime: Date(timeIntervalSince1970: 1_000))
        fs.seed("\(dir)/new.crash", text: try loadFixture("sample.crash"), mtime: Date(timeIntervalSince1970: 2_000))

        let result = XcodeCrashLoader(fs: fs).load(directories: [dir])

        #expect(result.crashes.count == 1)
        #expect(result.crashes[0].filePath.hasSuffix("new.crash"))
    }
}
