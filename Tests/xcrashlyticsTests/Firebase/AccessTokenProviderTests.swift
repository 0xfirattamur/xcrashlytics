import Foundation
import Testing
@testable import xcrashlytics

@Suite("FirebaseToolsTokenProvider")
struct FirebaseToolsTokenProviderTests {
    private let cfgPath = "/cfg/firebase-tools.json"

    private func provider(fs: FileSystem, http: HTTPTransport) -> FirebaseToolsTokenProvider {
        FirebaseToolsTokenProvider(fs: fs, httpTransport: http, configPath: cfgPath)
    }

    @Test("missing config throws firebaseLoginRequired")
    func missingConfig() async {
        let fs = InMemoryFileSystem()
        let p = provider(fs: fs, http: MockHTTPTransport())
        await #expect(throws: AccessTokenError.firebaseLoginRequired) {
            _ = try await p.token()
        }
    }

    @Test("isFirebaseLoggedIn detects refresh_token")
    func detection() {
        let fs = InMemoryFileSystem()
        fs.seed(cfgPath, text: #"{"tokens":{"refresh_token":"R"}}"#)
        let p = provider(fs: fs, http: MockHTTPTransport())
        #expect(p.isFirebaseLoggedIn() == true)
    }

    @Test("token endpoint success returns access_token")
    func tokenExchangeOK() async throws {
        let fs = InMemoryFileSystem()
        fs.seed(cfgPath, text: #"{"tokens":{"refresh_token":"R"}}"#)
        let http = MockHTTPTransport { _ in
            let body = Data(#"{"access_token":"ya29.x","token_type":"Bearer","expires_in":3599}"#.utf8)
            let r = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, r)
        }
        let p = provider(fs: fs, http: http)
        let token = try await p.token()
        #expect(token == "ya29.x")
    }

    @Test("token reuses cached access token until forced refresh")
    func tokenReusesCachedAccessToken() async throws {
        let fs = InMemoryFileSystem()
        fs.seed(cfgPath, text: #"{"tokens":{"refresh_token":"R"}}"#)
        var exchanges = 0
        let http = MockHTTPTransport { _ in
            exchanges += 1
            let body = Data(#"{"access_token":"ya29.cached","token_type":"Bearer","expires_in":3599}"#.utf8)
            let r = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, r)
        }
        let p = provider(fs: fs, http: http)

        let first = try await p.token()
        let second = try await p.token()
        let refreshed = try await p.forceRefresh()

        #expect(first == "ya29.cached")
        #expect(second == "ya29.cached")
        #expect(refreshed == "ya29.cached")
        #expect(exchanges == 2)
    }

    @Test("invalid_grant body surfaces refreshTokenInvalid")
    func invalidGrant() async {
        let fs = InMemoryFileSystem()
        fs.seed(cfgPath, text: #"{"tokens":{"refresh_token":"R"}}"#)
        let http = MockHTTPTransport { _ in
            let body = Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)
            let r = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, r)
        }
        let p = provider(fs: fs, http: http)
        do {
            _ = try await p.token()
            #expect(Bool(false), "expected throw")
        } catch {
            guard case .refreshTokenInvalid = error as? AccessTokenError else {
                #expect(Bool(false), "wrong error: \(error)")
                return
            }
        }
    }
}
