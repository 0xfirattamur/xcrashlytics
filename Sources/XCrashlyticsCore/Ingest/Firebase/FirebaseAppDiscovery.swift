//
//  FirebaseAppDiscovery.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

public struct DiscoveredFirebaseApp: Sendable, Equatable {
    public var profileName: String
    public var appId: String
    public var platform: String
    /// iOS `BUNDLE_ID` or Android `package_name`, when the config file has one.
    public var bundleId: String?
    public var sourcePath: String

    public init(profileName: String, appId: String, platform: String, bundleId: String? = nil, sourcePath: String) {
        self.profileName = profileName
        self.appId = appId
        self.platform = platform
        self.bundleId = bundleId
        self.sourcePath = sourcePath
    }
}

public struct FirebaseAppDiscovery: Sendable {
    private let fs: FileSystem

    public init(fs: FileSystem) {
        self.fs = fs
    }

    /// Directories holding build outputs or vendored copies — scanning them
    /// would turn one app into several duplicate profiles.
    static let skippedDirectories: Set<String> = [".build", "DerivedData", "Pods", "node_modules", "build", ".git"]

    public func discover(from root: String) throws -> [DiscoveredFirebaseApp] {
        func isScanned(_ path: String) -> Bool {
            !relativePath(path, root: root).split(separator: "/").dropLast()
                .contains { Self.skippedDirectories.contains(String($0)) }
        }
        let plistApps = try fs.enumerate(at: root, matchingExtensions: ["plist"])
            .filter { ($0 as NSString).lastPathComponent.hasSuffix("GoogleService-Info.plist") && isScanned($0) }
            .compactMap { path -> DiscoveredFirebaseApp? in
                guard let ids = try idsFromPlist(path: path) else { return nil }
                return DiscoveredFirebaseApp(
                    profileName: profileName(for: path, root: root),
                    appId: ids.appId,
                    platform: "ios",
                    bundleId: ids.bundleId,
                    sourcePath: relativePath(path, root: root)
                )
            }
        let jsonApps = try fs.enumerate(at: root, matchingExtensions: ["json"])
            .filter { ($0 as NSString).lastPathComponent == "google-services.json" && isScanned($0) }
            .compactMap { path -> DiscoveredFirebaseApp? in
                guard let ids = try idsFromGoogleServicesJSON(path: path) else { return nil }
                return DiscoveredFirebaseApp(
                    profileName: profileName(for: path, root: root),
                    appId: ids.appId,
                    platform: "android",
                    bundleId: ids.bundleId,
                    sourcePath: relativePath(path, root: root)
                )
            }
        return uniqueProfileNames(for: plistApps + jsonApps)
            .sorted { $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending }
    }

    private func idsFromPlist(path: String) throws -> (appId: String, bundleId: String?)? {
        let data = try fs.read(at: path)
        guard
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let appId = object["GOOGLE_APP_ID"] as? String,
            FirebaseClient.projectNumber(fromAppId: appId) != nil
        else {
            return nil
        }
        return (appId, (object["BUNDLE_ID"] as? String)?.trimmedNonEmpty)
    }

    private func idsFromGoogleServicesJSON(path: String) throws -> (appId: String, bundleId: String?)? {
        let data = try fs.read(at: path)
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let clients = object["client"] as? [[String: Any]]
        else {
            return nil
        }
        for client in clients {
            guard
                let info = client["client_info"] as? [String: Any],
                let appId = info["mobilesdk_app_id"] as? String,
                FirebaseClient.projectNumber(fromAppId: appId) != nil
            else {
                continue
            }
            let android = info["android_client_info"] as? [String: Any]
            return (appId, (android?["package_name"] as? String)?.trimmedNonEmpty)
        }
        return nil
    }

    private func profileName(for path: String, root: String) -> String {
        let relative = relativePath(path, root: root) as NSString
        let parent = relative.deletingLastPathComponent
        let raw = parent.isEmpty || parent == "." ? relative.deletingPathExtension : (parent as NSString).lastPathComponent
        return raw
            .replacingOccurrences(of: "GoogleService-Info", with: "")
            .replacingOccurrences(of: "google-services", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ ."))
            .lowercased()
    }

    private func relativePath(_ path: String, root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    private func uniqueProfileNames(for apps: [DiscoveredFirebaseApp]) -> [DiscoveredFirebaseApp] {
        var used = Set<String>()
        return apps.map { app in
            var copy = app
            var name = app.profileName
            var suffix = 2
            while used.contains(name) {
                name = "\(app.profileName)-\(suffix)"
                suffix += 1
            }
            copy.profileName = name
            used.insert(name)
            return copy
        }
    }
}
