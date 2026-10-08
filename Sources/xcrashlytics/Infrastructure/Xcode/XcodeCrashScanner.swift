import Foundation

struct XcodeCrashScanner: Sendable {
    private let fileStore: FileStore
    private static let supportedExtensions: Set<String> = ["crash", "ips"]

    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// Paths are sorted and deduplicated (directories may overlap). A missing directory
    /// is skipped silently; one that exists but cannot be enumerated yields a warning.
    func scan(directories: [String]) -> (paths: [String], warnings: [CommandWarning]) {
        var paths: [String] = []
        var warnings: [CommandWarning] = []
        for directory in directories {
            do {
                let found = try fileStore.listFiles(under: directory, withExtensions: Self.supportedExtensions)
                paths.append(contentsOf: found)
            } catch {
                warnings.append(CommandWarning(
                    code: .xcodeScanFailed,
                    message: "failed to scan \(directory): \(error.localizedDescription)",
                    path: directory))
            }
        }
        return (Set(paths).sorted(), warnings)
    }
}
