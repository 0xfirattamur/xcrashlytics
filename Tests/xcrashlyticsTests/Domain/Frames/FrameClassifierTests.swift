import Foundation
import Testing
@testable import xcrashlytics

@Suite("FrameClassifier")
struct FrameClassifierTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let frame: CrashlyticsFrame
        let appLibraries: Set<String>
        let isApp: Bool
        let isSystem: Bool
        var testDescription: String { name }

        init(
            _ name: String, symbol: String? = nil, file: String? = nil, library: String? = nil,
            owner: String? = nil, blamed: Bool = false, appLibraries: Set<String> = [], isApp: Bool, isSystem: Bool
        ) {
            self.name = name
            self.frame = CrashlyticsFrame(
                symbol: symbol, file: file, library: library, owner: owner, blamed: blamed)
            self.appLibraries = appLibraries
            self.isApp = isApp
            self.isSystem = isSystem
        }
    }

    static let classification: [Case] = [
        Case("DEVELOPER swift frame", symbol: "Checkout.pay()", file: "Checkout.swift", library: "MyApp",
             owner: "DEVELOPER", isApp: true, isSystem: false),
        Case("legacy APPLICATION owner", symbol: "run()", library: "MyApp", owner: "APPLICATION", isApp: true, isSystem: false),
        Case("VENDOR source file is third party, not app", symbol: "Alamofire.request", file: "Session.swift",
             library: "Alamofire", owner: "VENDOR", isApp: false, isSystem: false),
        Case("DEVELOPER CrashlyticsLogger is developer code", symbol: "CrashlyticsLogger.log(_:)",
             file: "CrashlyticsLogger.swift", library: "MyApp", owner: "DEVELOPER", isApp: true, isSystem: false),
        Case("unowned CrashlyticsLogger is not SDK noise", symbol: "CrashlyticsLogger.log(_:)", file: "Logger.swift",
             library: "MyApp", isApp: true, isSystem: false),
        Case("FIRCLS symbol", symbol: "FIRCLSUserLoggingRecordError", file: "FIRCLSUserLogging.m",
             owner: "THIRD_PARTY", blamed: true, isApp: false, isSystem: true),
        Case("FIRCrashlytics method", symbol: "-[FIRCrashlytics recordError:userInfo:]", file: "FIRCrashlytics.m",
             owner: "THIRD_PARTY", isApp: false, isSystem: true),
        Case("SDK library name", symbol: "record()", library: "FirebaseCrashlytics", isApp: false, isSystem: true),
        Case("Android SDK package", symbol: "com.google.firebase.crashlytics.internal.Foo.bar", file: "Foo.java",
             isApp: false, isSystem: true),
        Case("THIRD_PARTY owner decides nothing: project module source file", symbol: "BlurMLClassifier.predict()",
             file: "BlurMLClassifier.swift", library: "Core", owner: "THIRD_PARTY", isApp: true, isSystem: false),
        Case("SYSTEM libdispatch", symbol: "_dispatch_call_block_and_release", library: "libdispatch.dylib",
             owner: "SYSTEM", isApp: false, isSystem: true),
        Case("PLATFORM Foundation", symbol: "-[NSOperation start]", library: "Foundation", owner: "PLATFORM",
             isApp: false, isSystem: true),
        Case("RUNTIME owner", symbol: "swift_retain", library: "libswiftCore.dylib", owner: "RUNTIME", isApp: false, isSystem: true),
        Case("redacted symbol", symbol: "<redacted>", library: "MyApp", owner: "DEVELOPER", isApp: false, isSystem: true),
        Case("deduplicated symbol", symbol: "<deduplicated_symbol>", library: "Core", isApp: false, isSystem: true),
        Case("unowned UIKitCore frame", symbol: "-[UIApplication run]", library: "UIKitCore", isApp: false, isSystem: true),
        Case("unowned blamed frame without a file", symbol: "crash()", library: "MyApp", blamed: true, isApp: true, isSystem: false),
        Case("unowned frame without any evidence", symbol: "mystery", library: "MyApp", isApp: false, isSystem: false),
        Case("Kotlin source file", symbol: "MainActivity.onCreate", file: "MainActivity.kt", library: "app", isApp: true, isSystem: false),
        // Unknown or empty libraries are never app frames, whatever the owner says.
        Case("DEVELOPER frame without a library", symbol: nil, owner: "DEVELOPER", isApp: false, isSystem: false),
        Case("DEVELOPER frame with an empty library", symbol: "main", library: "", owner: "DEVELOPER", isApp: false, isSystem: false),
        Case("DEVELOPER frame with a '?' library", symbol: "main", file: "main.swift", library: "?", owner: "DEVELOPER",
             isApp: false, isSystem: false),
        Case("blamed frame without a library", symbol: "crash()", file: "Crash.swift", blamed: true, isApp: false, isSystem: false),
        // The SDK is recognised by symbol in whichever library it is linked into.
        Case("FIRCLS frame statically linked into the app's framework", symbol: "FIRCLSProcessRecordAllThreads",
             library: "KeyboardCore", owner: "THIRD_PARTY", isApp: false, isSystem: true),
        Case("__FIRCLS block symbol", symbol: "__FIRCLSExceptionRecord_block_invoke", library: "KeyboardCore",
             owner: "DEVELOPER", isApp: false, isSystem: true),
        Case("FIRCLS C++ handler", symbol: "FIRCLSTerminateHandler()", library: "KeyboardCore", isApp: false, isSystem: true),
        Case("Objective-C -[FIRCLS…] method", symbol: "-[FIRCLSReportAdapter init]", library: "MyApp",
             owner: "DEVELOPER", isApp: false, isSystem: true),
        Case("FIRCrashlytics class method", symbol: "+[FIRCrashlytics crashlytics]", library: "MyApp",
             owner: "DEVELOPER", isApp: false, isSystem: true),
        // First-party frameworks Firebase labels THIRD_PARTY, named by the profile.
        Case("THIRD_PARTY frame of a profile app library", symbol: "Engine.run()", library: "KeyboardCore",
             owner: "THIRD_PARTY", appLibraries: ["keyboardcore"], isApp: true, isSystem: false),
        Case("app library without symbol or file", library: "KeyboardCore", owner: "THIRD_PARTY",
             appLibraries: ["keyboardcore"], isApp: true, isSystem: false),
        Case("the same THIRD_PARTY frame without the profile entry", symbol: "Engine.run()", library: "KeyboardCore",
             owner: "THIRD_PARTY", isApp: false, isSystem: false),
        Case("SDK frames of an app library stay SDK", symbol: "FIRCLSHandler", library: "KeyboardCore",
             owner: "THIRD_PARTY", appLibraries: ["keyboardcore"], isApp: false, isSystem: true),
        Case("app libraries elsewhere in the profile do not change a system frame", symbol: "x", library: "UIKitCore",
             owner: "PLATFORM", appLibraries: ["keyboardcore"], isApp: false, isSystem: true),
        // Library names are matched case-insensitively, trimmed, and placeholders are not libraries.
        Case("profile library names match case-insensitively", symbol: "Engine.run()", library: "KEYBOARDCORE",
             owner: "THIRD_PARTY", appLibraries: ["KeyboardCore"], isApp: true, isSystem: false),
        Case("library names are trimmed", symbol: "run()", library: "  MyApp ", owner: "DEVELOPER", isApp: true, isSystem: false),
        Case("DEVELOPER frame with an 'Unknown' library", symbol: "main", library: "Unknown", owner: "DEVELOPER",
             isApp: false, isSystem: false),
        Case("DEVELOPER frame with an '<unknown>' library", symbol: "main", library: "<unknown>", owner: "DEVELOPER",
             isApp: false, isSystem: false)
    ]

    @Test("frame classification", arguments: classification)
    func classify(_ testCase: Case) {
        let classifier = FrameClassifier(appLibraries: testCase.appLibraries)
        #expect(classifier.isAppFrame(testCase.frame) == testCase.isApp)
        #expect(classifier.isSystemFrame(testCase.frame) == testCase.isSystem)
    }
}
