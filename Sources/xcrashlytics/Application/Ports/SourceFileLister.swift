/// Lists a checkout's files so a crash frame's bare file name can be resolved to a path.
protocol SourceFileLister: Sendable {
    /// Files below `directory` whose lowercased extension is `fileExtension`.
    func files(under directory: String, withExtension fileExtension: String) throws -> [String]
}
