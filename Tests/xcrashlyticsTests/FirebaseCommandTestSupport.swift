import Foundation
@testable import xcrashlytics

extension CommandContext {
    func withFirebaseHTTP(_ httpTransport: HTTPTransport) -> CommandContext {
        CommandContext(
            fileSystem: FirebaseToolsAuthFileSystem(base: fileSystem),
            processRunner: processRunner,
            clock: clock,
            httpTransport: FirebaseToolsAuthHTTPTransport(firebaseTransport: httpTransport),
            console: console
        )
    }
}

private final class FirebaseToolsAuthFileSystem: FileSystem, @unchecked Sendable {
    private let base: FileSystem
    private let configPath: String
    private let configData = Data(#"{"tokens":{"refresh_token":"test-refresh-token"}}"#.utf8)

    init(base: FileSystem) {
        self.base = base
        let home = NSString(string: "~").expandingTildeInPath
        self.configPath = "\(home)/.config/configstore/firebase-tools.json"
    }

    func fileExists(at path: String) -> Bool {
        path == configPath || base.fileExists(at: path)
    }

    func read(at path: String) throws -> Data {
        if path == configPath {
            return configData
        }
        return try base.read(at: path)
    }

    func write(_ data: Data, to path: String) throws {
        try base.write(data, to: path)
    }

    func atomicWrite(_ data: Data, to path: String) throws {
        try base.atomicWrite(data, to: path)
    }

    func enumerate(at path: String, matchingExtensions extensions: Set<String>) throws -> [String] {
        try base.enumerate(at: path, matchingExtensions: extensions)
    }

    func attributes(at path: String) throws -> FileAttributes {
        if path == configPath {
            return FileAttributes(size: configData.count, modificationDate: Date(timeIntervalSince1970: 0))
        }
        return try base.attributes(at: path)
    }

    func createDirectory(at path: String) throws {
        try base.createDirectory(at: path)
    }

    func delete(at path: String) throws {
        try base.delete(at: path)
    }
}

private final class FirebaseToolsAuthHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let firebaseTransport: HTTPTransport

    init(firebaseTransport: HTTPTransport) {
        self.firebaseTransport = firebaseTransport
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url == FirebaseToolsTokenProvider.tokenEndpoint {
            let body = Data(#"{"access_token":"test-access-token","expires_in":3600}"#.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (body, response)
        }
        return try await firebaseTransport.send(request)
    }
}
