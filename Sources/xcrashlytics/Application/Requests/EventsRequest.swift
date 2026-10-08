import Foundation

struct EventsRequest: Sendable {
    var issueIds: [String]
    var limit: Int?
    var latest: Bool
    var userId: String?
    var since: String?
    var frameFilter: FrameFilter
    var framesOnly: Bool
    var includeBreadcrumbs: Bool
    var dsymPaths: [String]

    var showsFramesOnly: Bool {
        framesOnly || frameFilter.appFramesOnly || frameFilter.noSystemFrames || frameFilter.crashingThreadOnly
    }
}
