import Foundation

extension Config {
    /// `nil` when the link names an app this config does not know: querying the
    /// active app would silently hit the wrong project.
    func appId(for link: FirebaseConsoleLink) -> String? {
        let match = profiles
            .sorted { $0.key < $1.key }
            .first {
                $0.value.bundleId?.caseInsensitiveCompare(link.bundleId) == .orderedSame
                    && $0.value.appId.split(separator: ":").dropFirst(2).first
                        .map({ $0.caseInsensitiveCompare(link.platform) == .orderedSame }) == true
            }
        if let match { return match.value.appId }
        return resolvedBundleId == nil ? resolvedAppId : nil
    }
}
