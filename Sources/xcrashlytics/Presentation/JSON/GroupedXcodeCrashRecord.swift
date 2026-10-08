import Foundation

struct GroupedXcodeCrashRecord: Encodable, Sendable {
    let event: CrashEventPayload
    let filePath: String
    let fileMtime: Date
    let fileSize: Int

    init(_ crash: XcodeCrash) {
        event = CrashEventPayload(crash.event)
        filePath = crash.filePath
        fileMtime = crash.fileMtime
        fileSize = crash.fileSize
    }
}
