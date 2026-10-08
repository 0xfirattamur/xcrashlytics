/// Hands files to the user's tools; fails with `EditorLaunchError` when the tool does.
protocol EditorLauncher: Sendable {
    func openSource(at path: String, line: Int?) throws
    func openFile(at path: String) throws
}
