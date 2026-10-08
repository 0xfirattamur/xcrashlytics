import Foundation

enum CrashingThreadWarningFactory {
    static let code = WarningCode.noCrashedThread

    static func warning(eventId: String) -> CommandWarning {
        CommandWarning(
            code: code,
            message: "\(eventId) has no crashed thread; --crashing-thread-only returned no frames for it.")
    }
}
