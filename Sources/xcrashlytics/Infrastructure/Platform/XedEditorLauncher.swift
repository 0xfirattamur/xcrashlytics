import Foundation

struct XedEditorLauncher: EditorLauncher {
    private let subprocessExecutor: SubprocessExecutor

    init(subprocessExecutor: SubprocessExecutor) {
        self.subprocessExecutor = subprocessExecutor
    }

    func openSource(at path: String, line: Int?) throws {
        // xed has no path:line syntax; the line goes through --line.
        let arguments = line.map { ["xed", "--line", "\($0)", path] } ?? ["xed", path]
        try run(executable: "/usr/bin/env", arguments: arguments, tool: "xed")
    }

    func openFile(at path: String) throws {
        try run(executable: "/usr/bin/open", arguments: [path], tool: "open")
    }

    private func run(executable: String, arguments: [String], tool: String) throws {
        let result = try subprocessExecutor.execute(executable: executable, arguments: arguments, standardInput: nil)
        guard result.exitCode == 0 else {
            throw EditorLaunchError(tool: tool, exitCode: result.exitCode, stderr: result.standardError.trimmedNonEmpty)
        }
    }
}
