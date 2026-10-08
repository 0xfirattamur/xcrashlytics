import Foundation

protocol FileStore: Sendable {
    func exists(at path: String) -> Bool
    func readData(at path: String) throws -> Data
    /// Readers see either the old or the new contents, never a partial file.
    func writeDataAtomically(_ data: Data, to path: String) throws
    /// Recursive; the result is sorted.
    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String]
    /// Directories named in `skippedDirectories` are not descended into.
    func listFiles(
        under path: String,
        withExtensions extensions: Set<String>,
        skippingDirectories skippedDirectories: Set<String>
    ) throws -> [String]
    func attributes(at path: String) throws -> FileAttributes
}
