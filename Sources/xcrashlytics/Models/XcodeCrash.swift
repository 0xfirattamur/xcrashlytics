import Foundation

/// A `CrashEvent` parsed from a local Xcode crash file, paired with its file
/// metadata (path, mtime, size). `event.id` is the canonical `XC-` id.
struct XcodeCrash: Codable, Sendable, Hashable {
    /// The parsed crash event.
    var event: CrashEvent
    /// Absolute path to the source `.crash` file.
    var filePath: String
    /// File modification time — used to sort recent crashes first.
    var fileMtime: Date
    /// File size in bytes.
    var fileSize: Int

}
