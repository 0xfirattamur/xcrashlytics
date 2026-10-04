//
//  CommandContext.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import XCrashlyticsCore

/// Production wiring of every protocol-shaped dependency the CLI needs.
///
/// Commands take a `CommandContext` instead of constructing their own dependencies
/// so tests can hand them an alternate context backed by in-memory fakes.
public struct CommandContext: Sendable {
    public let fileSystem: FileSystem
    public let processRunner: ProcessRunner
    public let clock: Clock
    public let console: CLIConsole
    public let httpClient: HTTPClient

    public init(
        fileSystem: FileSystem,
        processRunner: ProcessRunner,
        clock: Clock,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        console: CLIConsole = StandardConsole()
    ) {
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.clock = clock
        self.httpClient = httpClient
        self.console = console
    }

    /// Default production context: real disk, real subprocesses, real clock.
    public static func live() -> CommandContext {
        CommandContext(
            fileSystem: DiskFileSystem(),
            processRunner: ShellProcessRunner(),
            clock: SystemClock()
        )
    }

    func firebaseClient(appId override: String? = nil) throws -> FirebaseCrashlyticsClient {
        let config = try ConfigFile(fileSystem: fileSystem).load()
        guard let appId = override ?? config.resolvedAppId else {
            throw ConfigError.missingAppId
        }
        return try FirebaseClient(
            appId: appId,
            fileSystem: fileSystem,
            httpClient: httpClient
        )
    }
}
