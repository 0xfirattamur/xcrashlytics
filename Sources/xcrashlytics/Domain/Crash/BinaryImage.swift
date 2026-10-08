import Foundation

/// `StackFrame.address` resolves against the image whose memory range contains it:
/// `address - loadAddress` is the offset within the binary.
struct BinaryImage: Sendable, Hashable {
    var name: String
    /// Must match the dSYM's UUID.
    var uuid: String
    var loadAddress: UInt64
    var arch: String
    var path: String
}
