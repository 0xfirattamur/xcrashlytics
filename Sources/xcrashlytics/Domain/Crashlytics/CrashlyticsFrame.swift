import Foundation

struct CrashlyticsFrame: Sendable, Equatable {
    var symbol: String?
    var file: String?
    var line: Int?
    var library: String?
    var owner: String?
    var blamed: Bool
    var offset: String?
    var address: UInt64?
    var column: Int?
    /// Position in the unfiltered stack, so filtered output keeps the real indices.
    var stackIndex: Int?
    var firebaseSymbol: String?
    /// `dsym` once a local dSYM supplied `symbol`/`file`/`line`.
    var symbolicated: String?

    init(
        symbol: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        library: String? = nil,
        owner: String? = nil,
        blamed: Bool = false,
        offset: String? = nil,
        address: UInt64? = nil,
        column: Int? = nil,
        stackIndex: Int? = nil,
        firebaseSymbol: String? = nil,
        symbolicated: String? = nil
    ) {
        self.symbol = symbol
        self.file = file
        self.line = line
        self.library = library
        self.owner = owner
        self.blamed = blamed
        self.offset = offset
        self.address = address
        self.column = column
        self.stackIndex = stackIndex
        self.firebaseSymbol = firebaseSymbol
        self.symbolicated = symbolicated
    }
}
