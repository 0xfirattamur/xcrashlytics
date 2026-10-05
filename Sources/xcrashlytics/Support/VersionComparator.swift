import Foundation

enum VersionComparator {
    static func isAtLeast(_ value: String?, _ minimum: String) -> Bool {
        guard let value else { return false }
        let left = numericParts(value)
        let right = numericParts(minimum)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }
        return true
    }

    private static func numericParts(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}
