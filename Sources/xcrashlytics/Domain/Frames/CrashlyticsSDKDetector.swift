import Foundation

// Crashlytics quirk: a non-fatal is titled and blamed at the SDK's own `recordError` frame,
// the same for every non-fatal; the useful culprit is the app frame that called it.
struct CrashlyticsSDKDetector: Sendable {
    // Matched by SDK names rather than the word "crashlytics" alone, so a
    // developer's `CrashlyticsLogger` is not mistaken for the SDK.
    private let markers = ["fircls", "fircrashlytics", "firebasecrashlytics", "com.google.firebase.crashlytics"]

    func isCrashlyticsSDKCode(symbol: String? = nil, file: String? = nil, library: String? = nil) -> Bool {
        [symbol, file, library].compactMap { $0?.lowercased() }.contains { name in
            markers.contains { name.contains($0) }
        }
    }
}
