import Foundation

struct CrashDetailRequest: Sendable {
    var id: String
    var frameFilter: FrameFilter
    var crashDirectories: [String] = []
    /// Without one, events come from the 90-day maximum.
    var impactWindow: DateInterval?
    var dsymPaths: [String] = []
    var includesVersionRange = false
}
