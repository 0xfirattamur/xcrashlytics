import Foundation

struct ExceptionDescriptor: Sendable, Hashable {
    // Crashlytics quirk: Firebase issue summaries carry the issue kind here (`FATAL`,
    // `NON_FATAL`, `ANR`) instead of a Mach exception type; events carry the exception class.
    var exceptionType: String
    // Crashlytics quirk: Firebase issues carry the analyzer signal (`SIGNAL_EARLY`, `SIGNAL_FRESH`,
    // `SIGNAL_REGRESSED`, `SIGNAL_REPETITIVE`) instead of a POSIX signal.
    var signal: String?
    var subtype: String?
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
