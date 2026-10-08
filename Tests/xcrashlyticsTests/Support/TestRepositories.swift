import Foundation
@testable import xcrashlytics

extension FileConfigRepository {
    /// A repository over `fileStore` rooted at the process working directory,
    /// where commands under test look for `.xcrashlytics.json`.
    init(fileStore: FileStore) {
        self.init(fileStore: fileStore, workingDirectory: FileManager.default.currentDirectoryPath)
    }
}

extension OrganizerCrashRepository {
    static func organizerDirectories(bundleId: String) -> [String] {
        organizerDirectories(bundleId: bundleId, homeDirectory: HomeDirectoryLocator.path)
    }
}
