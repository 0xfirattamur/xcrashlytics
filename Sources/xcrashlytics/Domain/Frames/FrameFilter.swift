struct FrameFilter: Sendable, Equatable {
    var appFramesOnly = false
    var noSystemFrames = false
    var crashingThreadOnly = false

    static let none = FrameFilter()
}
