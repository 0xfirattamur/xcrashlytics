import Foundation

/// A crash's culprit identity, used to cluster same-root-cause crashes across
/// sources and across Firebase's over-split issues.
///
/// The `symbol` is the group key — normalized so a function that crashes in
/// several ways (different exception types, files, or build versions) collapses
/// into one group. `module` is display-only.
///
/// Firebase issues carry the culprit in their title (`[Module] File.swift -
/// Symbol`); local Xcode crashes carry it as the top non-runtime frame.
enum CrashSignature {
    struct Signature: Hashable, Sendable {
        /// Normalized culprit symbol — the grouping key.
        let symbol: String
        /// Owning module/binary, for display (`Core`, `Clean-Gallery`, …).
        let module: String?

        init(symbol: String, module: String?) {
            self.symbol = symbol
            self.module = module
        }
    }

    /// Derives a crash's signature, or `nil` when there's no usable culprit
    /// (e.g. an unsymbolicated local crash, or a Firebase issue with no title).
    static func of(_ event: CrashEvent) -> Signature? {
        switch event.source {
        case .firebase: return fromTitle(event.exception.description)
        case .xcode:    return fromFrames(event.frames)
        }
    }
    /// Derives a Firebase issue signature from its title.
    static func of(_ issue: CrashIssue) -> Signature? {
        fromTitle(issue.title)
    }

    /// Local crashes: the first symbol past runtime and generic termination plumbing.
    static func fromFrames(_ frames: [Frame]) -> Signature? {
        guard let frame = FrameNormalizer.meaningful(frames).first(where: {
            guard let symbol = $0.symbol, !symbol.isEmpty else { return false }
            return !genericTerminationSymbols.contains(normalize(symbol))
        }), let symbol = frame.symbol else { return nil }
        let module = frame.binaryName
            .replacingOccurrences(of: " [unsymbolicated]", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Signature(symbol: normalize(symbol), module: module.isEmpty ? nil : module)
    }

    private static let genericTerminationSymbols: Set<String> = [
        "_objc_terminate", "objc_terminate", "std::terminate()",
        "std::terminate", "abort", "trap", "fatalerror",
        "swift_fatalerror", "swift_concurrency_fatalerror",
        "__pthread_kill", "raise"
    ]

    /// Firebase issues: parse `[Module] File.swift - Symbol` (the message lives
    /// in the subtitle, so the title is just the culprit location).
    static func fromTitle(_ title: String?) -> Signature? {
        guard var text = title?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var module: String?
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            module = String(text[text.index(after: text.startIndex)..<close])
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        // "File.swift - Symbol" → keep the symbol (the last " - " segment).
        if let separator = text.range(of: " - ", options: .backwards) {
            text = String(text[separator.upperBound...])
        }
        let symbol = normalize(text)
        return symbol.isEmpty ? nil : Signature(symbol: symbol, module: module)
    }

    /// Lowercases and strips compiler decorations that don't change the culprit,
    /// so `specialized X` and `X` group together.
    static func normalize(_ symbol: String) -> String {
        var text = symbol.trimmingCharacters(in: .whitespaces)
        for prefix in ["specialized ", "static ", "@objc "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        return text.lowercased()
    }
}
