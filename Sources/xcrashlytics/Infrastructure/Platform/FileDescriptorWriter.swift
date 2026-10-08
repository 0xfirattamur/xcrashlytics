import Foundation

/// Raw `write(2)` loop. Unlike `FileHandle.write(_:)` it never raises an
/// Objective-C exception on `EPIPE`; it reports failure instead.
enum FileDescriptorWriter {
    static func write(_ text: String, to descriptor: Int32) -> Bool {
        var remaining = Array(text.utf8)[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            remaining = remaining.dropFirst(written)
        }
        return true
    }
}
