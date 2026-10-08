import Foundation

/// A closed stdout pipe (`xcrashlytics … | head`) ends the process quietly with exit 0:
/// `SIGPIPE` is ignored so the write fails with `EPIPE` instead of killing it mid-write.
struct StandardStreamConsole: Console {
    func writeOutput(_ text: String) {
        guard FileDescriptorWriter.write(text, to: STDOUT_FILENO) else { exit(0) }
    }

    func reportWarning(_ message: String) {
        writeDiagnostic("warning: \(message)\n")
    }

    func writeDiagnostic(_ text: String) {
        _ = FileDescriptorWriter.write(text, to: STDERR_FILENO)
    }

    static func ignoreBrokenPipeSignal() {
        signal(SIGPIPE, SIG_IGN)
    }
}
