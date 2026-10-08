import Foundation

// Xcode frames are symbolicated after parsing; Firebase frames arrive symbolicated, with
// `address` set only for native frames.
struct StackFrame: Sendable, Hashable {
    /// 0 is the crash site; frames kept by a filter keep their original position.
    var index: Int
    var binaryName: String
    var symbol: String?
    var file: String?
    var line: Int?
    var column: Int?
    /// Raw instruction pointer. For Firebase frames only native frames carry one.
    var address: UInt64?
    var imageUUID: String?
    var isSymbolicated: Bool
    var firebaseSymbol: String?
    /// How `symbol`/`file`/`line` were produced when not by Crashlytics: `dsym`.
    var symbolicated: String?

    init(
        index: Int,
        binaryName: String,
        symbol: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        address: UInt64? = nil,
        imageUUID: String? = nil,
        isSymbolicated: Bool = false,
        firebaseSymbol: String? = nil,
        symbolicated: String? = nil
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
        self.firebaseSymbol = firebaseSymbol
        self.symbolicated = symbolicated
    }
}
