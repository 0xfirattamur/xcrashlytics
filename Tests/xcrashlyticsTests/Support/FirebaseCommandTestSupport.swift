import Foundation
@testable import xcrashlytics

extension Platform {
    /// Routes Firebase traffic to `httpClient` and stubs the firebase-tools login.
    func withFirebaseHTTP(_ httpClient: HTTPClient) -> Platform {
        .testing(
            fileStore: FirebaseToolsAuthFileStoreStub(base: fileStore),
            subprocessExecutor: subprocessExecutor,
            dateProvider: dateProvider,
            httpClient: FirebaseToolsAuthHTTPClientStub(firebaseTransport: httpClient),
            console: console,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }
}

private final class FirebaseToolsAuthFileStoreStub: FileStore, @unchecked Sendable {
    private let base: FileStore
    private let configPath: String
    private let configData = Data(#"{"tokens":{"refresh_token":"test-refresh-token"}}"#.utf8)

    init(base: FileStore) {
        self.base = base
        self.configPath = FirebaseToolsTokenProvider.defaultConfigPath()
    }

    func exists(at path: String) -> Bool {
        path == configPath || base.exists(at: path)
    }

    func readData(at path: String) throws -> Data {
        if path == configPath {
            return configData
        }
        return try base.readData(at: path)
    }

    func writeDataAtomically(_ data: Data, to path: String) throws {
        try base.writeDataAtomically(data, to: path)
    }

    func listFiles(under path: String, withExtensions extensions: Set<String>) throws -> [String] {
        try base.listFiles(under: path, withExtensions: extensions)
    }

    func attributes(at path: String) throws -> FileAttributes {
        if path == configPath {
            return FileAttributes(size: configData.count, modificationDate: Date(timeIntervalSince1970: 0))
        }
        return try base.attributes(at: path)
    }
}

private final class FirebaseToolsAuthHTTPClientStub: HTTPClient, @unchecked Sendable {
    private let firebaseTransport: HTTPClient

    init(firebaseTransport: HTTPClient) {
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
