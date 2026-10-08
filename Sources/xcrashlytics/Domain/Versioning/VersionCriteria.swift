import Foundation

struct VersionCriteria: Equatable, Sendable {
    /// Same version, and the same build when one is given, as in `6.16.0 (937)`.
    var appVersion: String?
    /// At least this version.
    var sinceVersion: String?

    var isEmpty: Bool { appVersion == nil && sinceVersion == nil }

    /// Both selections must hold. `value` is compared against `--app-version`;
    /// `release` (default `value`) against `--since-version`, so a caller can pass
    /// the version with its build to one and the bare version to the other.
    func admits(_ value: String?, release: String? = nil) -> Bool {
        if let appVersion, !Self.isSame(value, as: appVersion) { return false }
        if let sinceVersion, !Self.isAtLeast(release ?? value, sinceVersion) { return false }
        return true
    }

    /// Unparseable values fall back to case-insensitive text equality.
    private static func isSame(_ value: String?, as expected: String) -> Bool {
        guard let value else { return false }
        guard let left = AppVersion(value), let right = AppVersion(expected) else {
            return value.caseInsensitiveCompare(expected) == .orderedSame
        }
        return left.isSameRelease(as: right)
    }

    private static func isAtLeast(_ value: String?, _ minimum: String) -> Bool {
        guard let value, let left = AppVersion(value), let right = AppVersion(minimum) else { return false }
        return left >= right
    }
}
