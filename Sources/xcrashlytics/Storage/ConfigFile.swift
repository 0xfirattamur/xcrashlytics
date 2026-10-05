//
//  ConfigFile.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Reads and writes `.xcrashlytics.json` in the current working directory.
struct ConfigFile: Sendable {
    private let path: String = "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    private let fileSystem: FileSystem

    init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    func load() throws -> Config {
        guard fileSystem.fileExists(at: path) else { return Config() }
        let data = try fileSystem.read(at: path)
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.invalidFile
        }
    }

    func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try fileSystem.atomicWrite(data, to: path)
    }
}
