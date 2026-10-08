import Foundation

/// An app version like `6.16.0`, `6.16.0-beta.2` or `6.16.0 (937)`.
/// Ordering and equality compare numbers and pre-release only; builds are ignored.
struct AppVersion: Comparable, Sendable {
    let numbers: [Int]
    /// A pre-release sorts below the same numbers without one.
    let prerelease: String?
    let build: String?

    /// Parses `[v]N(.N)*[-prerelease][+build][ (build)]`; anything else is nil.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let grammar = /v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?(?:\+([0-9A-Za-z.-]+))?(?:\s*\(([^)]*)\))?/
        guard let match = trimmed.wholeMatch(of: grammar) else { return nil }
        var numbers: [Int] = []
        for part in match.1.split(separator: ".") {
            guard let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.numbers = numbers
        self.prerelease = match.2.map(String.init)
        self.build = (match.3 ?? match.4).map(String.init)
    }

    static func require(_ value: String, flag: String) throws -> AppVersion {
        guard let version = AppVersion(value) else {
            throw InvalidInputError(
                "\(flag) '\(value)' is not a version; use dotted numbers such as 6.16.0 or 6.16.0-beta.1.")
        }
        return version
    }

    func isSameRelease(as expected: AppVersion) -> Bool {
        guard self == expected else { return false }
        guard let build = expected.build else { return true }
        return self.build?.caseInsensitiveCompare(build) == .orderedSame
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.compare(rhs) == .orderedSame
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.compare(rhs) == .orderedAscending
    }

    // MARK: - Comparison

    private func compare(_ other: AppVersion) -> ComparisonResult {
        let byNumbers = compareNumbers(other)
        if byNumbers != .orderedSame { return byNumbers }
        switch (prerelease, other.prerelease) {
        case (nil, nil): return .orderedSame
        case (nil, _?): return .orderedDescending
        case (_?, nil): return .orderedAscending
        case let (lhs?, rhs?): return Self.comparePrerelease(lhs, rhs)
        }
    }

    /// Missing trailing components count as zero, so `6.16` equals `6.16.0`.
    private func compareNumbers(_ other: AppVersion) -> ComparisonResult {
        let componentCount = max(numbers.count, other.numbers.count)
        for position in 0..<componentCount {
            let mine = position < numbers.count ? numbers[position] : 0
            let theirs = position < other.numbers.count ? other.numbers[position] : 0
            if mine != theirs { return mine < theirs ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Dot-separated identifiers: numeric ones compare as numbers and sort below text ones;
    /// when all shared identifiers tie, the shorter list sorts first.
    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".")
        let rightParts = rhs.split(separator: ".")
        for (leftPart, rightPart) in zip(leftParts, rightParts) {
            let result = compareIdentifiers(leftPart, rightPart)
            if result != .orderedSame { return result }
        }
        if leftParts.count == rightParts.count { return .orderedSame }
        return leftParts.count < rightParts.count ? .orderedAscending : .orderedDescending
    }

    private static func compareIdentifiers(_ left: Substring, _ right: Substring) -> ComparisonResult {
        switch (Int(left), Int(right)) {
        case let (leftNumber?, rightNumber?):
            if leftNumber == rightNumber { return .orderedSame }
            return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
        case (_?, nil): return .orderedAscending
        case (nil, _?): return .orderedDescending
        case (nil, nil):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }
    }
}
