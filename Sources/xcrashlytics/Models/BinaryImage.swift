import Foundation

/// A binary loaded into the crashed process — the app itself or any framework.
///
/// Each `Frame.address` is resolved by finding the image whose memory range
/// contains the address, then computing the slide:
/// `address - image.loadAddress = offset within binary`.
struct BinaryImage: Codable, Sendable, Hashable {
    /// Binary name (e.g. `MyApp`, `UIKit`, `libsystem_c.dylib`).
    var name: String
    /// 16-byte UUID identifying the exact build — must match the dSYM's UUID.
    var uuid: String
    /// Address where the binary was loaded in process memory.
    var loadAddress: UInt64
    /// CPU architecture (`arm64`, `x86_64`) — required by `atos`.
    var arch: String
    /// Original on-disk path of the binary on the device that crashed.
    var path: String

}
