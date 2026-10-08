import Foundation

struct FileStoreSourceFileLister: SourceFileLister {
    let fileStore: FileStore

    func files(under directory: String, withExtension fileExtension: String) throws -> [String] {
        try fileStore.listFiles(under: directory, withExtensions: [fileExtension])
    }
}
