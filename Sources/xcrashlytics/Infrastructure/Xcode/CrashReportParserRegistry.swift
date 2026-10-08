import Foundation

struct CrashReportParserRegistry: Sendable {
    private let fileStore: FileStore
    // The legacy parser accepts anything, so it must stay last.
    private let parsers: [CrashReportParser] = [IPSCrashParser(), LegacyCrashLogParser()]

    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    func parse(path: String) throws -> ParsedCrashReport {
        let data: Data
        do {
            data = try fileStore.readData(at: path)
        } catch {
            throw CrashReportParseError.ioError("could not read the file: \(error.localizedDescription)")
        }
        // Lossy: odd bytes in a thread or process name must not fail the file.
        return try parse(text: String(decoding: data, as: Unicode.UTF8.self), path: path)
    }

    func parse(text: String, path: String) throws -> ParsedCrashReport {
        guard let parser = parsers.first(where: { $0.canParse(text) }) else {
            throw CrashReportParseError.malformedHeader("not a recognised crash report format")
        }
        return try parser.parse(text: text, path: path)
    }
}
