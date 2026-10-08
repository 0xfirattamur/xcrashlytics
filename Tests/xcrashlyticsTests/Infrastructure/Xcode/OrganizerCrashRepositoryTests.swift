import Foundation
import Testing
@testable import xcrashlytics

// Simulates an unreadable directory.
private struct ThrowingFileStore: FileStore {
    struct Failure: Error {}
    func exists(at path: String) -> Bool { true }
    func readData(at path: String) throws -> Data { throw Failure() }
    func writeDataAtomically(_ data: Data, to path: String) throws { throw Failure() }
    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] { throw Failure() }
    func attributes(at path: String) throws -> FileAttributes { throw Failure() }
}

@Suite("OrganizerCrashRepository")
struct OrganizerCrashRepositoryTests {
    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("loads .crash files newest-first, surfaces malformed as warning, ignores other files")
    func loadsCrashDirectory() throws {
        let fileStore = InMemoryFileStore()
        let directoryPath = "/crashes"
        fileStore.seed(
            "\(directoryPath)/A-good.crash",
            text: try loadFixture("sample.crash"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        fileStore.seed(
            "\(directoryPath)/B-good.crash",
            text: try loadFixture("sample-symbolicated.crash")
                .replacingOccurrences(
                    of: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                    with: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                ),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )
        fileStore.seed(
            "\(directoryPath)/C-bad.crash",
            text: try loadFixture("malformed.crash"),
            modificationDate: Date(timeIntervalSince1970: 3_000)
        )
        // Organizer stores other log kinds next to crashes — not scanned.
        fileStore.seed("\(directoryPath)/D.xclaunchlog", text: "not a crash")

        let loader = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path)
        let result = loader.crashes(in: [directoryPath])

        #expect(result.crashes.count == 2)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.code == "XCODE_PARSE_FAILED")
        #expect(result.warnings.first?.path == "\(directoryPath)/C-bad.crash")

        // newest first by modificationDate — A is modificationDate=2000, B is modificationDate=1000
        #expect(result.crashes[0].filePath.hasSuffix("A-good.crash"))
        #expect(result.crashes[1].filePath.hasSuffix("B-good.crash"))
    }

    @Test("missing directory is silently skipped")
    func missingDirectory() {
        let fileStore = InMemoryFileStore()
        let loader = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path)
        let result = loader.crashes(in: ["/does/not/exist"])
        #expect(result.crashes.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("unreadable directory surfaces as a warning, not a crash or silence")
    func warnsOnUnreadableDirectory() {
        let loader = OrganizerCrashRepository(fileStore: ThrowingFileStore(), homeDirectory: HomeDirectoryLocator.path)
        let result = loader.crashes(in: ["/some/dir"])
        #expect(result.crashes.isEmpty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].code == "XCODE_SCAN_FAILED")
        #expect(result.warnings[0].path == "/some/dir")
    }

    @Test("duplicate incident keeps the source-located copy even when the raw twin is newer")
    func dedupesPreferringSourceLocatedCopy() throws {
        let fileStore = InMemoryFileStore()
        let directoryPath = "/crashes"
        // Raw twin (no source locations) is NEWER — must still lose.
        fileStore.seed(
            "\(directoryPath)/raw.crash",
            text: try loadFixture("sample.crash"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        fileStore.seed(
            "\(directoryPath)/symbolicated.crash",
            text: try loadFixture("sample-symbolicated.crash"),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )

        let result = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path).crashes(in: [directoryPath])

        #expect(result.crashes.count == 1)
        #expect(result.crashes[0].filePath.hasSuffix("symbolicated.crash"))
        #expect(result.crashes[0].event.frames.contains { $0.file != nil })
    }

    @Test("duplicate incident with equally useful copies keeps the newest")
    func dedupesEqualCopiesByMtime() throws {
        let fileStore = InMemoryFileStore()
        let directoryPath = "/crashes"
        fileStore.seed("\(directoryPath)/old.crash", text: try loadFixture("sample.crash"), modificationDate: Date(timeIntervalSince1970: 1_000))
        fileStore.seed("\(directoryPath)/new.crash", text: try loadFixture("sample.crash"), modificationDate: Date(timeIntervalSince1970: 2_000))

        let result = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path).crashes(in: [directoryPath])

        #expect(result.crashes.count == 1)
        #expect(result.crashes[0].filePath.hasSuffix("new.crash"))
    }

    @Test("scans .ips next to .crash; non-crash and corrupt reports become distinct, clean warnings")
    func loadsIPSAndReportsSkips() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/d/good.ips", text: try loadFixture("ips-crash.ips"))
        fileStore.seed("/d/hang.ips", text: try loadFixture("ips-hang.ips"))
        fileStore.seed("/d/broken.ips", text: try loadFixture("ips-corrupt.ips"))
        fileStore.seed("/d/old.crash", text: try loadFixture("sample.crash"))

        let result = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path).crashes(in: ["/d"])

        #expect(Set(result.crashes.map(\.event.id)) == [
            "XC-0A0A0A0A-1111-2222-3333-444444444444", "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        ])
        let byPath = Dictionary(uniqueKeysWithValues: result.warnings.map { ($0.path, $0) })
        #expect(result.warnings.count == 2)
        let hang = try #require(byPath["/d/hang.ips"])
        #expect(hang.code == "XCODE_UNSUPPORTED_REPORT")
        #expect(hang.message == "skipped /d/hang.ips: bug_type 298 is not a crash report (no exception or threads); only crash reports are supported")
        let broken = try #require(byPath["/d/broken.ips"])
        #expect(broken.code == "XCODE_PARSE_FAILED")
        // A sentence, not a Swift enum dump, and the path appears once.
        #expect(broken.message == "failed to parse /d/broken.ips: the .ips body after the header line is not valid JSON")
    }

    @Test("a .crash without Exception Type is a clean PARSE_FAILED message")
    func malformedMessageIsReadable() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/d/bad.crash", text: try loadFixture("malformed.crash"))
        let warning = try #require(OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path).crashes(in: ["/d"]).warnings.first)
        #expect(warning.code == "XCODE_PARSE_FAILED")
        #expect(!warning.message.contains("malformedHeader"))
        #expect(warning.message.hasPrefix("failed to parse /d/bad.crash: missing Exception Type"))
    }

    @Test("a report without crashed-thread frames loads but warns")
    func noFramesWarning() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/d/noframes.crash", text: """
        Incident Identifier: 11111111-2222-3333-4444-555555555555
        Exception Type:      EXC_CRASH (SIGABRT)
        Triggered by Thread: 4
        """)
        let result = OrganizerCrashRepository(fileStore: fileStore, homeDirectory: HomeDirectoryLocator.path).crashes(in: ["/d"])
        #expect(result.crashes.count == 1)
        #expect(result.warnings.map(\.code) == ["XCODE_NO_THREAD_FRAMES"])
    }

    @Test("a file reachable through overlapping directories is loaded once")
    func overlappingDirectories() throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/a/b/one.crash", text: try loadFixture("sample.crash"))
        let scan = XcodeCrashScanner(fileStore: fileStore).scan(directories: ["/a", "/a/b"])
        #expect(scan.paths == ["/a/b/one.crash"])
    }

    @Test("standard Organizer directories follow $HOME-aware HomeDirectoryLocator")
    func standardDirectories() {
        let products = "\(HomeDirectoryLocator.path)/Library/Developer/Xcode/Products"
        #expect(OrganizerCrashRepository.organizerDirectories(bundleId: "com.a.b.c") == [
            "\(products)/com.a.b.c", "\(products)/com.a.b"
        ])
        #expect(OrganizerCrashRepository.organizerDirectories(bundleId: "com.a") == ["\(products)/com.a"])
    }
}
