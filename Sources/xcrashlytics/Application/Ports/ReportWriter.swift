/// Persists a finished report where the user asked for it.
protocol ReportWriter: Sendable {
    /// Writes `text` atomically to `path` (a leading `~` means the home directory) and returns the path written.
    func write(_ text: String, to path: String) throws -> String
}
