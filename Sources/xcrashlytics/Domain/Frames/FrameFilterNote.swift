import Foundation

/// Why an event shows no frames, printed in place of an empty list so a reader never has to
/// guess whether the stack was absent or filtered away.
struct FrameFilterNote: Sendable, Equatable {
    /// Machine-readable cause: `no_app_frames`, `no_non_system_frames`,
    /// `no_crashed_thread`, `no_crashed_thread_frames`, or `no_frames`.
    var reason: String
    /// Crashlytics' blame frame's library, else the first library on the stack.
    var crashedLibrary: String?
    var appFramesAbsent: Bool
    init(event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector) {
        crashedLibrary = Self.crashedLibrary(in: event, selector: selector)
        appFramesAbsent = filter.appFramesOnly
        if filter.crashingThreadOnly, !event.hasCrashedThread {
            reason = "no_crashed_thread"
        } else if filter.appFramesOnly {
            reason = "no_app_frames"
        } else if filter.noSystemFrames {
            reason = "no_non_system_frames"
        } else if filter.crashingThreadOnly {
            reason = "no_crashed_thread_frames"
        } else {
            reason = "no_frames"
        }
    }

    static func ifEmpty(
        _ event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector, shownFrameCount: Int
    ) -> Self? {
        shownFrameCount == 0 ? Self(event: event, filter: filter, selector: selector) : nil
    }

    var textLine: String {
        let crashed = "crashed in \(crashedLibrary ?? "an unknown library")"
        switch reason {
        case "no_app_frames": return "(no app frames in this event; \(crashed))"
        case "no_non_system_frames": return "(no frames left after --no-system-frames; \(crashed))"
        case "no_crashed_thread": return "(this event has no crashed thread; \(crashed))"
        case "no_crashed_thread_frames": return "(the crashed thread has no frames; \(crashed))"
        default: return "(this event has no frames)"
        }
    }

    static func crashedLibrary(in event: CrashlyticsEvent, selector: FrameSelector) -> String? {
        if let library = FrameClassifier.knownLibrary(event.blameFrame?.library) { return library }
        return selector.stackFrames(from: event)
            .lazy.compactMap { FrameClassifier.knownLibrary($0.library) }.first
    }
}
