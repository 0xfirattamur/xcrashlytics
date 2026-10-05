import Foundation

/// A non-fatal problem found while loading local crashes.
struct CrashLoadWarning: Sendable, Equatable, Encodable {
    /// Stable machine code: `XCODE_SCAN_FAILED` or `XCODE_PARSE_FAILED`.
    var code: String
    var message: String
    /// File or directory the warning is about.
    var path: String

}

/// Result of loading crashes from disk — successful crashes plus per-file
/// warnings for ones that failed to parse.
struct XcodeCrashLoadResult: Sendable {
    /// Successfully parsed crashes, with file metadata attached.
    var crashes: [XcodeCrash]
    /// One entry per file that failed to parse and per directory that failed
    /// to enumerate — surfaced rather than thrown so a single broken file or
    /// unreadable directory doesn't break the whole scan.
    var warnings: [CrashLoadWarning]

}

/// Scans directories and parses every crash report found.
struct XcodeCrashLoader: Sendable {
    private let fs: FileSystem
    private let scanner: XcodeCrashScanner
    private let parser: CrashLogParser

    init(fs: FileSystem) {
        self.fs = fs
        self.scanner = XcodeCrashScanner(fs: fs)
        self.parser = CrashLogParser(fs: fs)
    }

    /// The Xcode Organizer download directory for `bundleId`, scanned
    /// recursively for reports inside `Crashes/Points/*.xccrashpoint`.
    static func standardDirectories(bundleId: String) -> [String] {
        let home = NSString(string: "~").expandingTildeInPath
        return ["\(home)/Library/Developer/Xcode/Products/\(bundleId)"]
    }

    /// Parses every scanned file. Unreadable directories and unparsable files
    /// become warnings instead of failing the whole load.
    func load(directories: [String]) -> XcodeCrashLoadResult {
        let scan = scanner.scan(directories: directories)
        var crashes: [XcodeCrash] = []
        var warnings = scan.warnings

        for path in scan.paths {
            do {
                let event = try parser.parse(path: path)
                let attrs = (try? fs.attributes(at: path))
                    ?? FileAttributes(size: 0, modificationDate: Date(timeIntervalSince1970: 0))
                crashes.append(XcodeCrash(
                    event: event,
                    filePath: path,
                    fileMtime: attrs.modificationDate,
                    fileSize: attrs.size
                ))
            } catch {
                warnings.append(CrashLoadWarning(
                    code: "XCODE_PARSE_FAILED", message: "failed to parse \(path): \(error)", path: path))
            }
        }

        crashes = Self.dedupedByIncident(crashes)
        // Sort newest-first by mtime.
        // Secondary key keeps order stable when two distinct incidents share an mtime.
        crashes.sort { ($0.fileMtime, $0.event.id) > ($1.fileMtime, $1.event.id) }
        return XcodeCrashLoadResult(crashes: crashes, warnings: warnings)
    }

    /// Organizer keeps multiple copies of one incident — e.g. a raw-address
    /// twin next to a symbolicated report. Keep the most useful copy per
    /// incident id; otherwise duplicate XC ids surface and `show`/`open`
    /// can pick the copy without source locations.
    private static func dedupedByIncident(_ crashes: [XcodeCrash]) -> [XcodeCrash] {
        var best: [String: XcodeCrash] = [:]
        for crash in crashes {
            if let current = best[crash.event.id], !isMoreUseful(crash, than: current) {
                continue
            }
            best[crash.event.id] = crash
        }
        return Array(best.values)
    }

    private static func isMoreUseful(_ a: XcodeCrash, than b: XcodeCrash) -> Bool {
        let aLocated = a.event.frames.filter { $0.file != nil }.count
        let bLocated = b.event.frames.filter { $0.file != nil }.count
        if aLocated != bLocated { return aLocated > bLocated }
        let aSymbolicated = a.event.frames.filter { $0.isSymbolicated }.count
        let bSymbolicated = b.event.frames.filter { $0.isSymbolicated }.count
        if aSymbolicated != bSymbolicated { return aSymbolicated > bSymbolicated }
        if a.fileMtime != b.fileMtime { return a.fileMtime > b.fileMtime }
        return a.filePath < b.filePath
    }
}
