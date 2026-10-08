struct InitRequest: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case scan
        case manual(appId: String, profile: String)
    }

    let mode: Mode
    let bundleId: String?
    let appLibraries: [String]

    static func validated(
        scan: Bool, appId: String?, profile: String?, bundleId: String?, appLibraries: [String]
    ) throws -> InitRequest {
        func trimmed(_ value: String?, flag: String) throws -> String? {
            guard let value else { return nil }
            guard let clean = value.trimmedNonEmpty else { throw InvalidInputError("\(flag) must not be empty.") }
            return clean
        }
        let appId = try trimmed(appId, flag: "--app-id")
        let profile = try trimmed(profile, flag: "--profile")?.lowercased()
        let bundleId = try trimmed(bundleId, flag: "--bundle-id")
        let libraries = try appLibraries.compactMap { try trimmed($0, flag: "--app-library") }
        if scan {
            guard appId == nil, profile == nil, bundleId == nil else {
                throw InvalidInputError(
                    "--scan discovers app ids, profiles, and bundle ids; drop --app-id/--profile/--bundle-id.")
            }
            return InitRequest(mode: .scan, bundleId: nil, appLibraries: libraries)
        }
        guard let appId, let profile else {
            throw InvalidInputError("pass --app-id and --profile, or --scan to discover them.")
        }
        return InitRequest(mode: .manual(appId: appId, profile: profile), bundleId: bundleId, appLibraries: libraries)
    }
}
