import Foundation

/// Strips per-build noise from frames so grouping can identify meaningful app
/// frames instead of runtime/SDK plumbing.
///
/// Normalization rules:
/// - Drop raw `address`, `imageUUID`, `file`, `line`, `column`.
/// - Keep `binaryName` lowercased.
/// - Strip block-offset suffixes from `symbol` (e.g. `… + 24` → `…`).
/// - Collapse raw load-address "symbols" (e.g. `0x000000018abc1234`) to empty,
///   since they vary per build and would otherwise look like distinct symbols.
enum FrameNormalizer {
    /// One normalized frame token.
    struct Token: Hashable, Sendable {
        let binary: String
        let symbol: String

        init(binary: String, symbol: String) {
            self.binary = binary
            self.symbol = symbol
        }
    }

    /// Normalizes a single frame; returns `nil` if the frame has neither a
    /// symbol nor a meaningful binary name.
    static func normalize(_ frame: Frame) -> Token? {
        let binary = frame.binaryName
            .replacingOccurrences(of: " [unsymbolicated]", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let stripped = (frame.symbol.map(stripOffsetSuffix) ?? "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        // A bare load address is per-build noise, not a symbol.
        let symbol = isAddressOnly(stripped) ? "" : stripped
        if binary.isEmpty && symbol.isEmpty { return nil }
        return Token(binary: binary, symbol: symbol)
    }

    /// Normalizes the first `topN` frames returned by `meaningful(_:)`.
    static func normalize(_ frames: [Frame], topN: Int = 8) -> [Token] {
        meaningful(frames).prefix(topN).compactMap(normalize)
    }

    /// Runtime libraries that commonly top unrelated crash stacks. App
    /// frameworks such as Foundation, UIKit and libobjc are excluded because
    /// they can be the real culprit.
    private static let noiseBinaries: Set<String> = [
        "libsystem_kernel.dylib",
        "libsystem_pthread.dylib",
        "libsystem_c.dylib",
        "libsystem_platform.dylib",
        "libswift_concurrency.dylib",
        "libswiftcore.dylib",
        "libdispatch.dylib",
        "libdyld.dylib",
        "dyld",
        "libc++abi.dylib"
    ]

    /// Frames outside `noiseBinaries`, or the input unchanged when every frame
    /// is noise, so a noise-only stack still has a signature.
    static func meaningful(_ frames: [Frame]) -> [Frame] {
        let kept = frames.filter { !isNoiseFrame($0) }
        return kept.isEmpty ? frames : kept
    }

    private static func isNoiseFrame(_ frame: Frame) -> Bool {
        let binary = frame.binaryName
            .replacingOccurrences(of: " [unsymbolicated]", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return noiseBinaries.contains(binary)
    }

    private static func stripOffsetSuffix(_ s: String) -> String {
        if let r = s.range(of: " + ", options: .backwards) {
            return String(s[..<r.lowerBound])
        }
        return s
    }

    /// True when `s` is just a hexadecimal load address — a `0x…` literal, or an
    /// unambiguously long (>= 8 char) bare hex blob. Short hex-looking real
    /// symbols (`cafe`, `dead`) are deliberately preserved.
    private static func isAddressOnly(_ s: String) -> Bool {
        if s.hasPrefix("0x") {
            let body = s.dropFirst(2)
            return !body.isEmpty && body.allSatisfy(\.isHexDigit)
        }
        return s.count >= 8 && s.allSatisfy(\.isHexDigit)
    }
}
