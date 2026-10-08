import Foundation

// Crashlytics quirk: an issue is titled by one frame (often the SDK's or a pod's), so the
// title alone can hide that every stack runs through one framework.
struct LibraryAttribution: Sendable, Equatable {
    /// Libraries on the crashed threads, each counted once per event, without
    /// system and Crashlytics SDK frames; most frequent first.
    var dominantLibraries: [Entry]
    var blameLibraries: [Entry]

    struct Entry: Sendable, Equatable {
        var library: String
        var events: Int
        /// `events` over all sampled events, rounded to 3 decimals.
        var share: Double
        /// Crashlytics' most frequent `owner` for the library's frames (`DEVELOPER`, `THIRD_PARTY`, …).
        var owner: String?
    }
}
