import Foundation

struct CrashExportRequest: Sendable {
    var id: String
    var since: String
    var frameFilter: FrameFilter
    var crashDirectories: [String]
}
