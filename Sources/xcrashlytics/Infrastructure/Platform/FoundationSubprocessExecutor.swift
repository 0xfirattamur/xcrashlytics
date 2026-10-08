import Foundation

struct FoundationSubprocessExecutor: SubprocessExecutor {
    /// A child spawned while another run's pipe ends are open and inheritable keeps them open,
    /// so neither side ever sees EOF. Pipes are made close-on-exec and launched under this lock.
    private static let launchLock = NSLock()

    func execute(executable: String, arguments: [String], standardInput: String?) throws -> SubprocessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipes = try Self.launch(process, withInput: standardInput != nil)

        // The child blocks once a pipe buffer (64 KB) is full, so stderr and stdin are served on
        // dedicated threads while this thread reads stdout. Not GCD: its default pool is capped
        // near the core count and can starve these blocking reads on small machines.
        let errorReader = PipeReader(pipes.error)
        let inputWriter = pipes.input.map { PipeWriter(standardInput ?? "", into: $0) }
        let output = pipes.output.fileHandleForReading.readDataToEndOfFile()
        let error = errorReader.waitForEndOfFile()
        inputWriter?.waitUntilWritten()
        process.waitUntilExit()

        return SubprocessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: output, encoding: .utf8) ?? "",
            standardError: String(data: error, encoding: .utf8) ?? ""
        )
    }

    private static func launch(_ process: Process, withInput: Bool) throws -> ProcessPipes {
        try launchLock.withLock {
            let pipes = ProcessPipes(input: withInput ? Pipe() : nil)
            pipes.markCloseOnExec()
            process.standardOutput = pipes.output
            process.standardError = pipes.error
            if let inputPipe = pipes.input { process.standardInput = inputPipe }
            try process.run()
            return pipes
        }
    }
}

private struct ProcessPipes {
    let output = Pipe()
    let error = Pipe()
    let input: Pipe?

    /// The child still gets its ends: launching dup2s them onto 0, 1 and 2, which clears the flag.
    func markCloseOnExec() {
        for pipe in [output, error] + [input].compactMap({ $0 }) {
            _ = fcntl(pipe.fileHandleForReading.fileDescriptor, F_SETFD, FD_CLOEXEC)
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        }
    }
}

/// Reads a pipe to end of file on its own thread.
private final class PipeReader: @unchecked Sendable {
    private let finished = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ pipe: Pipe) {
        Thread {
            self.data = pipe.fileHandleForReading.readDataToEndOfFile()
            self.finished.signal()
        }.start()
    }

    func waitForEndOfFile() -> Data {
        finished.wait()
        return data
    }
}

/// Writes the child's standard input on its own thread, then closes it so the child sees EOF.
private final class PipeWriter: @unchecked Sendable {
    private let finished = DispatchSemaphore(value: 0)

    init(_ text: String, into pipe: Pipe) {
        let data = Data(text.utf8)
        Thread {
            try? pipe.fileHandleForWriting.write(contentsOf: data)
            try? pipe.fileHandleForWriting.close()
            self.finished.signal()
        }.start()
    }

    func waitUntilWritten() {
        finished.wait()
    }
}
