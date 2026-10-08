import Foundation

/// Every golden case. Adding a case is one line in one of the tables, in `GoldenCases*.swift`.
enum GoldenCases {
    static let all: [GoldenCase] = .flatten([help, issues, events, show, export, groups, blame, breakdown, open, setup, failures])

    /// An FB- id that every table shares.
    static let fatal = "FB-I1"
    static let nonFatal = "FB-I2"
    static let noCrashedThread = "FB-I3"
    static let xcode = "XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    static let xcodeIPS = "XC-0A0A0A0A-1111-2222-3333-444444444444"
    static let crashDir = GoldenWorld.crashDirectory
    static let consoleLink = "https://console.firebase.google.com/project/golden/crashlytics/app/ios:com.example.app/issues/I1"
}

extension Array where Element == GoldenCase {
    static func flatten(_ groups: [[GoldenCase]]) -> [GoldenCase] { groups.flatMap { $0 } }

    /// One case per output format: `<stem>-text` (no flag), `<stem>-json`, `<stem>-ndjson`.
    static func formats(
        _ stem: String, _ arguments: [String], _ formats: [String] = ["text", "json", "ndjson"], world: GoldenWorld = GoldenWorld()
    ) -> [GoldenCase] {
        formats.map { format in
            GoldenCase("\(stem)-\(format)", format == "text" ? arguments : arguments + ["--format", format], world: world)
        }
    }
}

extension GoldenWorld {
    static let noConfig = GoldenWorld(config: .missing)
    static let widget = GoldenWorld(config: .widgetActive)
}
