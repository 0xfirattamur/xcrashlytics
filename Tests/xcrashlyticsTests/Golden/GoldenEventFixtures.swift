// swiftlint:disable line_length
import Foundation

/// Synthetic Crashlytics `events` bodies. User `user-secret-1` appears in every
/// free-text field so a golden proves nothing leaks it.
enum GoldenEvents {
    /// Newest `I1` event: a fatal NSException with crash info, custom keys, logs, breadcrumbs, a user id and
    /// frames of the app, a first-party framework, the system and a library a dSYM can symbolicate.
    static let fatalWithEverything = #"""
    {
      "name": "projects/1234567890/apps/1:1234567890:ios:aaaa1111bbbb2222/events/SESS1_E1",
      "eventId": "E1",
      "eventTime": "2026-06-14T09:30:00Z",
      "platform": "IOS",
      "bundleOrPackage": "com.example.app",
      "processState": "FOREGROUND",
      "issue": {"id": "I1", "title": "[ExampleApp] BlurService.swift - BlurService.classify(_:)", "subtitle": "Fatal error: Array index out of range"},
      "issueTitle": "[ExampleApp] BlurService.swift - BlurService.classify(_:)",
      "issueSubtitle": "Fatal error: Array index out of range",
      "version": {"displayVersion": "6.16.0", "buildVersion": "937", "displayName": "6.16.0 (937)"},
      "device": {"model": "iPhone15,2", "orientation": "PORTRAIT"},
      "operatingSystem": {"displayVersion": "17.5.1", "jailbroken": false, "orientation": "PORTRAIT"},
      "memory": {"free": "120000000", "used": "3400000000"},
      "storage": {"free": "52000000000", "used": "76000000000"},
      "user": {"id": "user-secret-1"},
      "blameFrame": {"symbol": "BlurService.classify(_:)", "file": "BlurService.swift", "line": 77, "library": "ExampleApp", "owner": "DEVELOPER", "address": "4096", "blamed": true},
      "exceptions": [
        {
          "type": "NSInvalidArgumentException",
          "exceptionMessage": "-[NSNull length]: unrecognized selector sent to instance 0x1 (user user-secret-1)",
          "title": "Fatal Exception: NSInvalidArgumentException",
          "blamed": true,
          "frames": [
            {"symbol": "<redacted>", "library": "CoreFoundation", "owner": "PLATFORM", "address": "620768"},
            {"symbol": "BlurService.classify(_:)", "file": "BlurService.swift", "line": 77, "library": "ExampleApp", "owner": "DEVELOPER", "address": "4096"}
          ]
        }
      ],
      "threads": [
        {
          "crashed": true,
          "title": "Crashed: com.apple.main-thread",
          "signal": "SIGABRT",
          "signalCode": "0x0",
          "crashAddress": "0",
          "queue": "com.apple.main-thread",
          "frames": [
            {"symbol": "objc_exception_throw", "library": "libobjc.A.dylib", "owner": "PLATFORM", "address": "6400"},
            {"symbol": "<redacted>", "library": "CoreFoundation", "owner": "PLATFORM", "address": "620768"},
            {"symbol": "objectdestroyTm", "library": "KeyboardCore", "owner": "THIRD_PARTY", "address": "2092404", "offset": "32256"},
            {"symbol": "BlurService.classify(_:)", "file": "BlurService.swift", "line": 77, "library": "ExampleApp", "owner": "DEVELOPER", "address": "4096", "blamed": true},
            {"symbol": "ExampleViewController.viewDidLoad()", "file": "ExampleViewController.swift", "line": 42, "library": "ExampleApp", "owner": "DEVELOPER", "address": "8192"},
            {"symbol": "UIApplicationMain", "library": "UIKitCore", "owner": "PLATFORM", "address": "900"}
          ]
        },
        {
          "title": "Thread #1",
          "frames": [
            {"symbol": "mach_msg2_trap", "library": "libsystem_kernel.dylib", "owner": "PLATFORM", "address": "7000"}
          ]
        }
      ],
      "customKeys": {
        "crash_info_entry_0": "BlurService.swift:77: Fatal error: Array index out of range (user user-secret-1)",
        "crash_info_entry_1": "second entry",
        "nserror-domain": "com.example.BlurError",
        "userId": "user-secret-1",
        "feature_flag": "dark_mode"
      },
      "logs": [
        {"logTime": "2026-06-14T09:29:58Z", "message": "opened camera for user-secret-1"},
        {"logTime": "2026-06-14T09:29:59Z", "message": "classify start"}
      ],
      "breadcrumbs": [
        {"eventTime": "2026-06-14T09:29:50Z", "title": "screen_view", "params": {"screen": "camera", "userId": "user-secret-1"}},
        {"eventTime": "2026-06-14T09:29:55Z", "title": "tap_blur", "params": {"strength": "3"}}
      ]
    }
    """#

    /// Older `I1` event from another user and version: an NSException only, no crash info.
    static let olderFatal = #"""
    {
      "name": "projects/1234567890/apps/1:1234567890:ios:aaaa1111bbbb2222/events/SESS2_E2",
      "eventId": "E2",
      "eventTime": "2026-06-12T08:00:00Z",
      "platform": "IOS",
      "bundleOrPackage": "com.example.app",
      "processState": "BACKGROUND",
      "version": {"displayVersion": "6.15.0", "buildVersion": "900", "displayName": "6.15.0 (900)"},
      "device": {"model": "iPhone14,5"},
      "operatingSystem": {"displayVersion": "17.4"},
      "user": {"id": "user-other-2"},
      "exceptions": [
        {"type": "CALayerInvalidGeometry", "exceptionMessage": "CALayer bounds contains NaN", "title": "Fatal Exception: CALayerInvalidGeometry", "blamed": true,
         "frames": [{"symbol": "<redacted>", "library": "QuartzCore", "owner": "PLATFORM", "address": "100"}]}
      ],
      "threads": [
        {
          "crashed": true,
          "title": "Crashed: com.apple.main-thread",
          "signal": "SIGABRT",
          "frames": [
            {"symbol": "BlurService.classify(_:)", "file": "BlurService.swift", "line": 80, "library": "ExampleApp", "owner": "DEVELOPER", "address": "4200", "blamed": true},
            {"symbol": "UIApplicationMain", "library": "UIKitCore", "owner": "PLATFORM", "address": "900"}
          ]
        }
      ]
    }
    """#

    /// A non-fatal `recordError` with the Crashlytics SDK frames above the app frame.
    static let nonFatal = #"""
    {
      "name": "projects/1234567890/apps/1:1234567890:ios:aaaa1111bbbb2222/events/SESS3_E3",
      "eventId": "E3",
      "eventTime": "2026-06-14T10:00:00Z",
      "platform": "IOS",
      "bundleOrPackage": "com.example.app",
      "version": {"displayVersion": "6.16.0", "buildVersion": "937", "displayName": "6.16.0 (937)"},
      "device": {"model": "iPhone15,2"},
      "operatingSystem": {"displayVersion": "17.5.1"},
      "user": {"id": "user-secret-1"},
      "errors": [
        {
          "title": "Non-fatal Exception: com.example.NetworkError",
          "subtitle": "Domain: com.example.NetworkError",
          "blamed": true,
          "frames": [
            {"symbol": "-[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]", "file": "FIRCLSNonFatalError.m", "line": 33, "library": "Core", "owner": "THIRD_PARTY", "address": "100"},
            {"symbol": "-[FIRCrashlytics recordError:userInfo:]", "file": "FIRCrashlytics.m", "line": 435, "library": "Core", "owner": "THIRD_PARTY", "address": "200"},
            {"symbol": "NetworkClient.recordFailure(error:)", "file": "NetworkClient.swift", "line": 186, "library": "ExampleApp", "owner": "DEVELOPER", "address": "300"},
            {"symbol": "UIApplicationMain", "library": "UIKitCore", "owner": "PLATFORM", "address": "900"}
          ]
        }
      ],
      "customKeys": {"retry": "2", "userId": "user-secret-1"},
      "logs": [{"logTime": "2026-06-14T09:59:00Z", "message": "request failed for user-secret-1"}]
    }
    """#

    /// An event whose threads include none flagged as crashed.
    static let noCrashedThread = #"""
    {
      "name": "projects/1234567890/apps/1:1234567890:ios:aaaa1111bbbb2222/events/SESS4_E4",
      "eventId": "E4",
      "eventTime": "2026-06-13T07:15:00Z",
      "platform": "IOS",
      "bundleOrPackage": "com.example.app",
      "version": {"displayVersion": "6.16.0", "buildVersion": "937", "displayName": "6.16.0 (937)"},
      "device": {"model": "iPhone14,5"},
      "operatingSystem": {"displayVersion": "17.4"},
      "user": {"id": "user-other-2"},
      "threads": [
        {
          "title": "Thread #0",
          "frames": [
            {"symbol": "MapRenderer.draw(_:)", "file": "MapRenderer.swift", "line": 301, "library": "ExampleApp", "owner": "DEVELOPER", "address": "5000"},
            {"symbol": "CA::Layer::display()", "library": "QuartzCore", "owner": "PLATFORM", "address": "600"}
          ]
        }
      ]
    }
    """#

    /// Minimal fatal for issues that only need an event to exist.
    static func simpleFatal(id: String, time: String, symbol: String, file: String, version: String = "6.16.0") -> String {
        #"""
        {
          "name": "projects/1234567890/apps/1:1234567890:ios:aaaa1111bbbb2222/events/SESS_\#(id)",
          "eventId": "\#(id)",
          "eventTime": "\#(time)",
          "platform": "IOS",
          "bundleOrPackage": "com.example.app",
          "version": {"displayVersion": "\#(version)", "buildVersion": "937", "displayName": "\#(version) (937)"},
          "device": {"model": "iPhone15,2"},
          "operatingSystem": {"displayVersion": "17.5.1"},
          "user": {"id": "user-other-2"},
          "threads": [
            {"crashed": true, "title": "Crashed: com.apple.main-thread", "signal": "SIGSEGV", "frames": [
              {"symbol": "\#(symbol)", "file": "\#(file)", "line": 12, "library": "ExampleApp", "owner": "DEVELOPER", "address": "4096", "blamed": true},
              {"symbol": "UIApplicationMain", "library": "UIKitCore", "owner": "PLATFORM", "address": "900"}
            ]}
          ]
        }
        """#
    }
}
// swiftlint:enable line_length
