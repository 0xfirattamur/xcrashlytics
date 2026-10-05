import Foundation

/// One stack frame within a crashed thread.
///
/// A frame starts life with just an `address` (raw instruction pointer) and a
/// `binaryName`. After symbolication via `atos`, `symbol`, `file`, `line`, and `column` are filled in and `isSymbolicated` flips to `true`.
struct Frame: Codable, Sendable, Hashable {
    /// Position in the stack — 0 is the top (crash site).
    var index: Int
    /// Name of the binary that contained this call (e.g. `MyApp`, `UIKit`).
    var binaryName: String
    /// Demangled function name, once symbolicated.
    var symbol: String?
    /// Source file path, if available from the dSYM.
    var file: String?
    /// Source line number, if available.
    var line: Int?
    /// Source column number, if available.
    var column: Int?
    /// Raw instruction pointer in process memory. `nil` for Firebase frames —
    /// the API reports symbols, not addresses.
    var address: UInt64?
    /// UUID of the binary image — needed to locate the matching dSYM.
    var imageUUID: String?
    /// `true` once `symbol` (and optionally `file`/`line`) have been filled in.
    var isSymbolicated: Bool

    init(
        index: Int,
        binaryName: String,
        symbol: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        address: UInt64? = nil,
        imageUUID: String? = nil,
        isSymbolicated: Bool = false
    ) {
        self.index = index
        self.binaryName = binaryName
        self.symbol = symbol
        self.file = file
        self.line = line
        self.column = column
        self.address = address
        self.imageUUID = imageUUID
        self.isSymbolicated = isSymbolicated
    }
}
