//
//  ConfigFile.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Reads and writes the project-local `.xcrashlytics.json`.
///
/// The config lives at `<current directory>/.xcrashlytics.json` — each project
/// owns its own, so multiple apps coexist with zero flags. Run commands from the
/// repo root.
///
public struct ConfigFile: Sendable {
    private let path: String = "\(FileManager.default.currentDirectoryPath)/.xcrashlytics.json"
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public func load() throws -> Config {
        guard fileSystem.fileExists(at: path) else { return Config() }
        let data = try fileSystem.read(at: path)
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.invalidFile
        }
    }

    public func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try fileSystem.atomicWrite(data, to: path)
    }
}
