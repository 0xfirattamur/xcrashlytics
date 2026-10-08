import Foundation

struct FileStoreReportWriter: ReportWriter {
    let fileStore: FileStore

    func write(_ text: String, to path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        try fileStore.writeDataAtomically(Data(text.utf8), to: expanded)
        return expanded
    }
}
