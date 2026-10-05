import Foundation

/// Top-level "what killed the process" summary extracted from a crash report.
struct ExceptionInfo: Codable, Sendable, Hashable {
    /// Mach exception type (e.g. `EXC_BAD_ACCESS`, `EXC_CRASH`).
    var exceptionType: String
    /// POSIX signal that delivered the kill (e.g. `SIGSEGV`, `SIGABRT`).
    var signal: String?
    /// Optional subtype detail (e.g. `KERN_INVALID_ADDRESS at 0x0...`).
    var subtype: String?
    /// Free-form description (unused by the `.crash` parser; Firebase fills it).
    var description: String?

    init(
        exceptionType: String,
        signal: String? = nil,
        subtype: String? = nil,
        description: String? = nil
    ) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.subtype = subtype
        self.description = description
    }
}
