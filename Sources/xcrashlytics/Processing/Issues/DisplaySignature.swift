//
//  DisplaySignature.swift
//  xcrashlytics
//

import Foundation

/// Module / file / symbol parsed from a Firebase issue title of the form
/// `[Module] File.swift - Symbol`.
struct DisplaySignature: Sendable, Equatable {
    var module: String?
    var file: String?
    var symbol: String?

    init?(_ issue: CrashIssue) {
        guard var text = issue.exception.description?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            module = String(text[text.index(after: text.startIndex)..<close])
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        if let separator = text.range(of: " - ", options: .backwards) {
            file = String(text[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            symbol = String(text[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            symbol = text
        }
    }
}
