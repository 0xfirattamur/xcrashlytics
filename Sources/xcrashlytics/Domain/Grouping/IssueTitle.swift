import Foundation

// Crashlytics quirk: titles read `[Module] File.swift - Symbol`; the message lives in the subtitle.
struct IssueTitle: Equatable, Sendable {
    let module: String?
    let file: String?
    let symbol: String

    init?(_ title: String?) {
        guard var text = title?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var module: String?
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            module = String(text[text.index(after: text.startIndex)..<close])
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        var file: String?
        if let separator = text.range(of: " - ", options: .backwards) {
            file = String(text[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            text = String(text[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        self.module = module
        self.file = file
        self.symbol = text
    }

    // Crashlytics quirk: a non-fatal is titled at the SDK's own recordError frame,
    // so such a title names no culprit.
    var namesCrashlyticsSDK: Bool {
        CrashlyticsSDKDetector().isCrashlyticsSDKCode(symbol: symbol, file: file)
    }
}
