import Foundation

/// Where a crash report originated.
///
/// xcrashlytics aggregates crashes from two places:
/// Firebase Crashlytics (cloud) and Xcode-produced local logs (`.crash`).
enum CrashSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// Crash fetched from Firebase Crashlytics.
    case firebase
    /// Crash parsed from a local Xcode `.crash` file.
    case xcode
}
