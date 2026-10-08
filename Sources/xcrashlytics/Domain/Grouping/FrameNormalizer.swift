import Foundation

enum FrameNormalizer {
    // Foundation, UIKit and libobjc are deliberately absent: they can be the real culprit.
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

    static func meaningful(_ frames: [StackFrame]) -> [StackFrame] {
        let kept = frames.filter { !isNoiseFrame($0) }
        return kept.isEmpty ? frames : kept
    }

    private static func isNoiseFrame(_ frame: StackFrame) -> Bool {
        let binary = frame.binaryName
            .replacingOccurrences(of: " [unsymbolicated]", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return noiseBinaries.contains(binary)
    }

    // Short hex-looking real symbols (`cafe`, `dead`) are kept: only `0x…` or >= 8 hex chars count.
    static func isAddressOnly(_ text: String) -> Bool {
        if text.hasPrefix("0x") {
            let body = text.dropFirst(2)
            return !body.isEmpty && body.allSatisfy(\.isHexDigit)
        }
        return text.count >= 8 && text.allSatisfy(\.isHexDigit)
    }
}
