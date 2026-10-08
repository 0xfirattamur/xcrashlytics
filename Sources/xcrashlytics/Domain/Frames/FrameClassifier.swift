import Foundation

struct FrameClassifier: Sendable {
    let appLibraries: Set<String>
    let sdkDetector: CrashlyticsSDKDetector

    init(appLibraries: Set<String> = [], sdkDetector: CrashlyticsSDKDetector = CrashlyticsSDKDetector()) {
        self.appLibraries = Set(appLibraries.map { $0.lowercased() })
        self.sdkDetector = sdkDetector
    }

    // Crashlytics quirk: `owner` is DEVELOPER, VENDOR, RUNTIME, PLATFORM or SYSTEM, but live
    // events also carry THIRD_PARTY on a project's own frameworks, so that value decides
    // nothing and `appLibraries` or the library/file heuristics apply.
    /// Crashlytics SDK code is never app code even though it is often statically linked
    /// into the app's own framework.
    func isAppFrame(_ frame: CrashlyticsFrame) -> Bool {
        guard let library = Self.knownLibrary(frame.library) else {
            return false
        }
        if isRedactedOrDeduplicated(frame) || isSDKFrame(frame) {
            return false
        }
        if appLibraries.contains(library.lowercased()) {
            return true
        }
        switch ownerClass(frame) {
        case .developer:
            return true
        case .system, .vendor:
            return false
        case .unknown:
            break
        }
        if isKnownSystemLibrary(library) {
            return false
        }
        if frame.blamed {
            return true
        }
        return frame.file.map(isLikelySourceFile) ?? false
    }

    /// What `--no-system-frames` drops: redacted, SDK, and OS frames. Vendor frames
    /// stay because they are library code, not the system's.
    func isSystemFrame(_ frame: CrashlyticsFrame) -> Bool {
        if isRedactedOrDeduplicated(frame) || isSDKFrame(frame) {
            return true
        }
        if let library = Self.knownLibrary(frame.library), appLibraries.contains(library.lowercased()) {
            return false
        }
        switch ownerClass(frame) {
        case .developer:
            return false
        case .system:
            return true
        case .vendor, .unknown:
            return isKnownSystemLibrary(frame.library)
        }
    }

    func isSDKFrame(_ frame: CrashlyticsFrame) -> Bool {
        sdkDetector.isCrashlyticsSDKCode(symbol: frame.symbol, file: frame.file, library: frame.library)
    }

    static func knownLibrary(_ library: String?) -> String? {
        guard let name = library?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return ["?", "unknown", "<unknown>"].contains(name.lowercased()) ? nil : name
    }

    private enum OwnerClass {
        case developer, vendor, system, unknown
    }

    private func ownerClass(_ frame: CrashlyticsFrame) -> OwnerClass {
        switch frame.owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "developer", "application", "app": return .developer
        case "vendor": return .vendor
        case "system", "platform", "runtime": return .system
        default: return .unknown
        }
    }

    private func isRedactedOrDeduplicated(_ frame: CrashlyticsFrame) -> Bool {
        guard let symbol = frame.symbol?.lowercased() else { return false }
        return symbol == "<redacted>" || symbol == "<deduplicated_symbol>"
    }

    private func isKnownSystemLibrary(_ library: String?) -> Bool {
        guard let library = library?.lowercased() else { return false }
        return library.hasPrefix("libsystem")
            || library.hasPrefix("libdispatch")
            || library.hasPrefix("libobjc")
            || library.hasPrefix("libswift")
            || library == "uikit"
            || library == "uikitcore"
            || library == "foundation"
            || library == "corefoundation"
            || library == "swiftui"
            || library == "quartzcore"
            || library == "graphicsservices"
            || library == "dyld"
    }

    private func isLikelySourceFile(_ file: String) -> Bool {
        let lowercased = file.lowercased()
        return lowercased.hasSuffix(".swift")
            || lowercased.hasSuffix(".m")
            || lowercased.hasSuffix(".mm")
            || lowercased.hasSuffix(".c")
            || lowercased.hasSuffix(".cc")
            || lowercased.hasSuffix(".cpp")
            || lowercased.hasSuffix(".kt")
            || lowercased.hasSuffix(".kts")
            || lowercased.hasSuffix(".java")
    }
}
