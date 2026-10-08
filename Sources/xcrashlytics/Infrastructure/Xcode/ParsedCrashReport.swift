import Foundation

struct ParsedCrashReport: Sendable {
    var event: CrashEvent
    var warnings: [CommandWarning] = []

    static func noThreadFramesWarning(reason: String, path: String) -> CommandWarning {
        CommandWarning(
            code: .xcodeNoThreadFrames,
            message: "\(path): \(reason); this crash has no stack frames to group by",
            path: path)
    }
}
