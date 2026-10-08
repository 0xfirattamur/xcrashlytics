import Foundation

struct FirebaseAppDiscoverer: AppDiscovery {
    private let fileStore: FileStore

    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    // Build outputs and vendored copies would turn one app into several duplicate profiles.
    static let skippedDirectories: Set<String> = [
        ".build", "DerivedData", "Pods", "node_modules", "build", ".git", "Carthage", "SourcePackages",
    ]

    // MARK: - App discovery

    func discover(from root: String) throws -> AppDiscoveryResult {
        var unreadable: [String] = []
        var apps: [DiscoveredFirebaseApp] = []
        for kind in ConfigFileKind.allCases {
            let scan = try scanConfigFiles(of: kind, under: root)
            apps += scan.apps
            unreadable += scan.unreadable
        }
        let namedApps = bundleAwareNames(apps)
            .sorted { $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending }
        let appLibraries = try detectAppLibraries(from: root)
        return AppDiscoveryResult(apps: namedApps, unreadable: unreadable, appLibraries: appLibraries)
    }

    private enum ConfigFileKind: CaseIterable {
        case iosPlist
        case androidJSON

        var fileExtension: String {
            switch self {
            case .iosPlist: return "plist"
            case .androidJSON: return "json"
            }
        }

        var platform: String {
            switch self {
            case .iosPlist: return "ios"
            case .androidJSON: return "android"
            }
        }

        func isConfigFile(named fileName: String) -> Bool {
            switch self {
            case .iosPlist: return fileName.hasSuffix("GoogleService-Info.plist")
            case .androidJSON: return fileName == "google-services.json"
            }
        }
    }

    private struct AppIdentifiers {
        var appId: String
        var bundleId: String?
    }

    private struct ConfigScan {
        var apps: [DiscoveredFirebaseApp] = []
        var unreadable: [String] = []
    }

    private func scanConfigFiles(of kind: ConfigFileKind, under root: String) throws -> ConfigScan {
        let paths = try fileStore.listFiles(
            under: root, withExtensions: [kind.fileExtension], skippingDirectories: Self.skippedDirectories)
        var scan = ConfigScan()
        for path in paths where kind.isConfigFile(named: (path as NSString).lastPathComponent) {
            let sourcePath = relativePath(path, root: root)
            // A template with `$(GOOGLE_APP_ID)` or a non-dictionary plist: report it, don't skip silently.
            guard let identifiers = try? readIdentifiers(of: kind, atPath: path) else {
                scan.unreadable.append(sourcePath)
                continue
            }
            scan.apps.append(DiscoveredFirebaseApp(
                profileName: profileName(for: path, root: root),
                appId: identifiers.appId,
                platform: kind.platform,
                bundleId: identifiers.bundleId,
                sourcePath: sourcePath
            ))
        }
        return scan
    }

    private func readIdentifiers(of kind: ConfigFileKind, atPath path: String) throws -> AppIdentifiers? {
        switch kind {
        case .iosPlist: return try idsFromPlist(path: path)
        case .androidJSON: return try idsFromGoogleServicesJSON(path: path)
        }
    }

    // Firebase may label frames of these as `THIRD_PARTY` although the repo owns the code.
    private static let libraryProductTypes: Set<String> = [
        "com.apple.product-type.framework",
        "com.apple.product-type.framework.static",
        "com.apple.product-type.library.static",
    ]

    // MARK: - App libraries

    func detectAppLibraries(from root: String) throws -> [String] {
        var names = Set<String>()
        let projectPaths = try fileStore.listFiles(
            under: root, withExtensions: ["pbxproj"], skippingDirectories: Self.skippedDirectories)
        for path in projectPaths {
            guard let objects = projectObjects(atPath: path) else { continue }
            names.formUnion(libraryNames(in: objects))
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func projectObjects(atPath path: String) -> [String: Any]? {
        guard let data = try? fileStore.readData(at: path),
              let project = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        else { return nil }
        return project["objects"] as? [String: Any]
    }

    private func libraryNames(in objects: [String: Any]) -> [String] {
        var names: [String] = []
        for case let target as [String: Any] in objects.values {
            guard target["isa"] as? String == "PBXNativeTarget",
                  let type = target["productType"] as? String, Self.libraryProductTypes.contains(type),
                  let name = Self.productName(of: target, objects: objects)
            else { continue }
            names.append(name)
        }
        return names
    }

    // `productName` may be a build-setting reference (`$(TARGET_NAME)`); then use the product file's name.
    private static func productName(of target: [String: Any], objects: [String: Any]) -> String? {
        if let name = (target["productName"] as? String)?.trimmedNonEmpty, !name.contains("$") { return name }
        if let name = nameFromProductFile(of: target, objects: objects) { return name }
        return (target["name"] as? String)?.trimmedNonEmpty.flatMap { $0.contains("$") ? nil : $0 }
    }

    private static func nameFromProductFile(of target: [String: Any], objects: [String: Any]) -> String? {
        guard let reference = target["productReference"] as? String,
              let path = (objects[reference] as? [String: Any])?["path"] as? String
        else { return nil }
        var stem = (path as NSString).deletingPathExtension
        if path.hasSuffix(".a"), stem.hasPrefix("lib") { stem = String(stem.dropFirst(3)) }
        guard let name = stem.trimmedNonEmpty, !name.contains("$") else { return nil }
        return name
    }

    // MARK: - Config file parsing

    private func idsFromPlist(path: String) throws -> AppIdentifiers? {
        let data = try fileStore.readData(at: path)
        guard
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let appId = object["GOOGLE_APP_ID"] as? String,
            FirebaseAppId.projectNumber(from: appId) != nil
        else {
            return nil
        }
        return AppIdentifiers(appId: appId, bundleId: (object["BUNDLE_ID"] as? String)?.trimmedNonEmpty)
    }

    private func idsFromGoogleServicesJSON(path: String) throws -> AppIdentifiers? {
        let data = try fileStore.readData(at: path)
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
                FirebaseAppId.projectNumber(from: appId) != nil
            else {
                continue
            }
            let android = info["android_client_info"] as? [String: Any]
            return AppIdentifiers(appId: appId, bundleId: (android?["package_name"] as? String)?.trimmedNonEmpty)
        }
        return nil
    }

    // MARK: - Profile naming

    private func profileName(for path: String, root: String) -> String {
        let relative = relativePath(path, root: root) as NSString
        let parent = relative.deletingLastPathComponent
        let isAtScanRoot = parent.isEmpty || parent == "."
        let rawName = isAtScanRoot ? relative.deletingPathExtension : (parent as NSString).lastPathComponent
        let name = rawName
            .replacingOccurrences(of: "GoogleService-Info", with: "")
            .replacingOccurrences(of: "google-services", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ ."))
            .lowercased()
        // A config file at the scan root has no distinguishing directory name.
        return name.isEmpty ? "default" : name
    }

    private func relativePath(_ path: String, root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    private func uniqueProfileNames(for apps: [DiscoveredFirebaseApp]) -> [DiscoveredFirebaseApp] {
        let names = Self.uniqueNames(apps.map(\.profileName), priority: Array(apps.indices))
        return zip(apps, names).map { app, name in
            var copy = app
            copy.profileName = name
            return copy
        }
    }

    /// Earlier entries of `priority` (indices into `names`) keep their name when two collide.
    private static func uniqueNames(_ names: [String], priority: [Int]) -> [String] {
        var used = Set<String>()
        var unique = names
        for index in priority {
            var name = names[index]
            var suffix = 2
            while used.contains(name) {
                name = "\(names[index])-\(suffix)"
                suffix += 1
            }
            unique[index] = name
            used.insert(name)
        }
        return unique
    }

    // An app whose bundle id is another discovered id plus `.<suffix>` is an extension: named by the
    // suffix and linked via `extensionOf`; the app itself is `app`. Config files sharing one bundle
    // id are environments and keep their folder-derived names.
    private func bundleAwareNames(_ apps: [DiscoveredFirebaseApp]) -> [DiscoveredFirebaseApp] {
        let plan = extensionPlan(apps)
        guard !plan.isEmpty else { return uniqueProfileNames(for: apps) }
        var renamed = apps
        for (index, entry) in plan { renamed[index].profileName = entry.name }
        // Planned names win collisions over folder-derived names.
        let priority = renamed.indices.sorted { lhs, rhs in
            (plan[lhs] == nil ? 1 : 0, lhs) < (plan[rhs] == nil ? 1 : 0, rhs)
        }
        let names = Self.uniqueNames(renamed.map(\.profileName), priority: priority)
        return renamed.indices.map { index in
            var app = renamed[index]
            app.profileName = names[index]
            app.extensionOf = plan[index]?.parent.map { names[$0] }
            return app
        }
    }

    private struct PlannedName {
        var name: String
        var parent: Int?
    }

    /// The apps of one platform that declare a bundle id, indexed into the full app list.
    private struct PlatformBundles {
        let apps: [DiscoveredFirebaseApp]
        let indices: [Int]
        let bundleIds: Set<String>

        init(apps: [DiscoveredFirebaseApp], platform: String) {
            self.apps = apps
            self.indices = apps.indices.filter { apps[$0].platform == platform && apps[$0].bundleId != nil }
            self.bundleIds = Set(indices.compactMap { apps[$0].bundleId })
        }

        /// The longest other bundle id this one extends as `<parent>.<suffix>`.
        func parent(of bundleId: String) -> String? {
            bundleIds.filter { bundleId.hasPrefix($0 + ".") }.max { $0.count < $1.count }
        }

        func suffix(of bundleId: String, under parent: String) -> String {
            String(bundleId.dropFirst(parent.count + 1)).lowercased()
        }

        func appIndices(withBundleId bundleId: String) -> [Int] {
            indices.filter { apps[$0].bundleId == bundleId }
        }
    }

    // Maps app index to its bundle-derived name and, for extensions, the index of the app it extends.
    private func extensionPlan(_ apps: [DiscoveredFirebaseApp]) -> [Int: PlannedName] {
        var plan: [Int: PlannedName] = [:]
        for platform in Set(apps.map(\.platform)) {
            let bundles = PlatformBundles(apps: apps, platform: platform)
            let extensionBundleIds = bundles.bundleIds.filter { bundles.parent(of: $0) != nil }
            plan.merge(hostAppNames(in: bundles, extensionBundleIds: extensionBundleIds)) { current, _ in current }
            plan.merge(extensionNames(in: bundles, extensionBundleIds: extensionBundleIds)) { current, _ in current }
        }
        return plan
    }

    // A host app that has extensions is named `app`, unless an extension already took that suffix.
    private func hostAppNames(in bundles: PlatformBundles, extensionBundleIds: Set<String>) -> [Int: PlannedName] {
        let hostBundleIds = Set(extensionBundleIds.compactMap(bundles.parent(of:))).subtracting(extensionBundleIds)
        var takenSuffixes = Set(extensionBundleIds.compactMap { bundleId in
            bundles.parent(of: bundleId).map { bundles.suffix(of: bundleId, under: $0) }
        })
        var names: [Int: PlannedName] = [:]
        for bundleId in hostBundleIds.sorted() {
            let members = bundles.appIndices(withBundleId: bundleId)
            guard members.count == 1 else { continue }
            let lastComponent = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
            let fallbackName = lastComponent.lowercased()
            let name = takenSuffixes.contains("app") ? fallbackName : "app"
            takenSuffixes.insert(name)
            names[members[0]] = PlannedName(name: name, parent: nil)
        }
        return names
    }

    private func extensionNames(in bundles: PlatformBundles, extensionBundleIds: Set<String>) -> [Int: PlannedName] {
        var names: [Int: PlannedName] = [:]
        for bundleId in extensionBundleIds.sorted() {
            guard let hostBundleId = bundles.parent(of: bundleId) else { continue }
            let suffix = bundles.suffix(of: bundleId, under: hostBundleId)
            let members = bundles.appIndices(withBundleId: bundleId)
            let hostIndex = bundles.appIndices(withBundleId: hostBundleId)
                .min { bundles.apps[$0].profileName < bundles.apps[$1].profileName }
            for index in members {
                let name = members.count == 1 ? suffix : "\(suffix)-\(bundles.apps[index].profileName)"
                names[index] = PlannedName(name: name, parent: hostIndex)
            }
        }
        return names
    }
}
