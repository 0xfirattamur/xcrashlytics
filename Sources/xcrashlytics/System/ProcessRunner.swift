//
//  ProcessRunner.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Result of running an external command.
struct ProcessResult: Sendable, Equatable {
    /// Process exit code (0 = success).
    var exitCode: Int32
    /// Captured stdout as UTF-8 string.
    var stdout: String
    /// Captured stderr as UTF-8 string.
    var stderr: String

}

/// Abstraction over launching external commands (e.g. `atos`, `mdfind`).
///
/// Tests swap in `MockProcessRunner` to script per-command responses without
/// actually executing anything. Production uses `ShellProcessRunner`.
protocol ProcessRunner: Sendable {
    /// Runs `executable` with the given `arguments` synchronously.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the binary to launch.
    ///   - arguments: Command-line arguments, not including argv[0].
    ///   - stdin: Optional UTF-8 string fed to the child's stdin.
    /// - Returns: Exit code plus captured stdout/stderr.
    /// - Throws: If the process could not be spawned at all.
    func run(executable: String, arguments: [String], stdin: String?) throws -> ProcessResult
}

/// Production `ProcessRunner` impl using `Foundation.Process`.
struct ShellProcessRunner: ProcessRunner {
    func run(executable: String, arguments: [String], stdin: String?) throws -> ProcessResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            proc.standardInput = inPipe
            try proc.run()
            if let data = stdin.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            try? inPipe.fileHandleForWriting.close()
        } else {
            try proc.run()
        }

        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
