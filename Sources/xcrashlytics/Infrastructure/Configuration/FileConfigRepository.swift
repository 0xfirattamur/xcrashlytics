import Foundation

struct FileConfigRepository: ConfigRepository {
    private let fileStore: FileStore
    private let path: String

    init(fileStore: FileStore, workingDirectory: String) {
        self.fileStore = fileStore
        self.path = "\(workingDirectory)/.xcrashlytics.json"
    }

    func load() throws -> Config {
        guard fileStore.exists(at: path) else { return Config() }
        let data = try fileStore.readData(at: path)
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.invalidFile
        }
    }

    func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config) + Data("\n".utf8)
        try fileStore.writeDataAtomically(data, to: path)
    }
}
