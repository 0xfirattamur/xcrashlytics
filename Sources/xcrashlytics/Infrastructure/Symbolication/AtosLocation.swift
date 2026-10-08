import Foundation

/// One line of `atos` output: `symbol (in Library) (file:line)`.
struct AtosLocation: Sendable, Equatable {
    var symbol: String
    var file: String?
    var line: Int?

    init(symbol: String, file: String? = nil, line: Int? = nil) {
        self.symbol = symbol
        self.file = file
        self.line = line
    }

    // Nil for a line `atos` could not resolve: it echoes the address back, without `(in …)`.
    init?(line text: String) {
        guard let marker = text.range(of: " (in ", options: .backwards),
              let close = text[marker.upperBound...].firstIndex(of: ")")
        else { return nil }
        let symbol = String(text[..<marker.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return nil }
        self.symbol = symbol
        let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("("), rest.hasSuffix(")"), let colon = rest.lastIndex(of: ":") else { return }
        let file = String(rest[rest.index(after: rest.startIndex)..<colon])
        let digits = rest[rest.index(after: colon)..<rest.index(before: rest.endIndex)]
        // `<stdin>:0` and `:0` are atos' "no line info" answers, not locations.
        guard !file.isEmpty, !file.hasPrefix("<"), let number = Int(digits), number > 0 else { return }
        self.file = file
        self.line = number
    }
}
