import Foundation

struct XcodeCrash: Sendable, Hashable {
    var event: CrashEvent
    var filePath: String
    var fileMtime: Date
    var fileSize: Int
}
