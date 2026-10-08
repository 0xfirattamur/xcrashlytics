import ArgumentParser
import Foundation

enum OptionValidator {
    static func requirePositive(_ value: Int, flag: String) throws {
        guard value >= 1 else {
            throw ValidationError("\(flag) must be at least 1; got \(value).")
        }
    }

    static func requirePositive(_ value: Int?, flag: String) throws {
        if let value { try requirePositive(value, flag: flag) }
    }

    /// A present flag value must carry text; an empty filter would silently match nothing.
    static func requireNonEmpty(_ value: String?, flag: String) throws {
        if let value, value.trimmedNonEmpty == nil {
            throw ValidationError("\(flag) must not be empty.")
        }
    }
}
