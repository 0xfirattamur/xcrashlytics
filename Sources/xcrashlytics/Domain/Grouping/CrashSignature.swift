import Foundation

/// Culprit identity that clusters same-root-cause crashes across sources. `symbol` is the
/// normalized group key (so one function crashing in several ways collapses); `module` is display-only.
enum CrashSignature {
    struct Value: Hashable, Sendable {
        let symbol: String
        let module: String?

        init(symbol: String, module: String?) {
            self.symbol = symbol
            self.module = module
        }
    }

    static func of(_ event: CrashEvent) -> Value? {
        switch event.source {
        case .firebase: return fromTitle(event.exception.description)
        case .xcode:    return fromFrames(event.frames, images: event.binaryImages)
        }
    }
    static func of(_ issue: CrashIssue) -> Value? {
        fromTitle(issue.title)
    }

    // Crashlytics quirk: it blames the first app-owned frame (app, embedded SDKs, extensions).
    // Raw-address symbols change with every launch's ASLR slide, so they never form a signature,
    // and neither do generic termination frames such as `abort`.
    static func fromFrames(_ frames: [StackFrame], images: [BinaryImage] = []) -> Value? {
        let candidates = FrameNormalizer.meaningful(frames).filter(hasUsableSymbol)
        let appOwned = candidates.first { frame in
            SymbolicationAdvisor.image(for: frame, in: images).map(SymbolicationAdvisor.isAppOwned) == true
        }
        guard let frame = appOwned ?? candidates.first, let symbol = frame.symbol else { return nil }
        let module = frame.binaryName
            .replacingOccurrences(of: " [unsymbolicated]", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Value(symbol: normalize(symbol), module: module.isEmpty ? nil : module)
    }

    private static func hasUsableSymbol(_ frame: StackFrame) -> Bool {
        guard let symbol = frame.symbol?.trimmingCharacters(in: .whitespaces), !symbol.isEmpty,
              !FrameNormalizer.isAddressOnly(symbol) else { return false }
        let normalized = normalize(symbol)
        return !normalized.isEmpty && !genericTerminationSymbols.contains(normalized)
    }

    private static let genericTerminationSymbols: Set<String> = [
        "_objc_terminate", "objc_terminate", "std::terminate()",
        "std::terminate", "abort", "trap", "fatalerror",
        "swift_fatalerror", "swift_concurrency_fatalerror",
        "__pthread_kill", "raise"
    ]

    static func fromTitle(_ title: String?) -> Value? {
        guard let title = IssueTitle(title), !title.namesCrashlyticsSDK else { return nil }
        let symbol = normalize(title.symbol)
        return symbol.isEmpty ? nil : Value(symbol: symbol, module: title.module)
    }

    private static let decorationPrefixes = [
        "static ", "specialized ", "@objc ", "merged ", "partial apply for "
    ]

    private static let closurePrefix = try? NSRegularExpression(pattern: #"^(implicit )?closure #\d+( \([^)]*\))? in "#)
    private static let genericSpecializationPrefix =
        try? NSRegularExpression(pattern: #"^generic specialization <[^>]*> of "#)

    /// Strips compiler decorations so `static specialized closure #2 in X.y<T>(_:) [inlined]`
    /// and `X.y(_:)` group together; mangled (`$s…`) names are kept.
    static func normalize(_ symbol: String) -> String {
        var text = symbol.replacingOccurrences(of: "[inlined]", with: "")
            .trimmingCharacters(in: .whitespaces)
        while let stripped = strippingOneDecoration(from: text) {
            text = stripped
        }
        return collapseWhitespace(removeGenericArguments(text)).lowercased()
    }

    /// The text without its leading decoration, or nil when it has none.
    private static func strippingOneDecoration(from text: String) -> String? {
        if let prefix = decorationPrefixes.first(where: { text.hasPrefix($0) }) {
            return String(text.dropFirst(prefix.count))
        }
        for regex in [closurePrefix, genericSpecializationPrefix] {
            if let remainder = removingLeadingMatch(of: regex, from: text) { return remainder }
        }
        return nil
    }

    private static func removingLeadingMatch(of regex: NSRegularExpression?, from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range), match.range.location == 0,
              let matchedRange = Range(match.range, in: text) else { return nil }
        return String(text[matchedRange.upperBound...])
    }

    /// Drops balanced `<…>` generic argument lists that follow an identifier,
    /// leaving operator names such as `static func < (_:_:)` alone.
    private static func removeGenericArguments(_ text: String) -> String {
        var stripped = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "<", followsIdentifier(stripped), let end = matchingAngleBracket(in: text, from: index) {
                index = text.index(after: end)
                continue
            }
            stripped.append(char)
            index = text.index(after: index)
        }
        return stripped
    }

    private static func followsIdentifier(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last.isLetter || last.isNumber || last == "_" || last == ">"
    }

    /// Index of the `>` closing the `<` at `start`; a `>` preceded by `-` is a
    /// function arrow, not a closer.
    private static func matchingAngleBracket(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var previous: Character?
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if char == "<" { depth += 1 }
            if char == ">" && previous != "-" {
                depth -= 1
                if depth == 0 { return index }
            }
            previous = char
            index = text.index(after: index)
        }
        return nil
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
