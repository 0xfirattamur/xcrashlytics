import Foundation

struct AppDiscoveryResult: Sendable, Equatable {
    var apps: [DiscoveredFirebaseApp]
    var unreadable: [String]
    var appLibraries: [String] = []

    static let empty = AppDiscoveryResult(apps: [], unreadable: [])
}
