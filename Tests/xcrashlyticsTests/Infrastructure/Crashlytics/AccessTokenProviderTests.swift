import Foundation
import Testing
@testable import xcrashlytics

@Suite("FirebaseToolsTokenProvider")
struct FirebaseToolsTokenProviderTests {
    private let cfgPath = "/cfg/firebase-tools.json"

    private func seededFileStore(refreshToken: String = "R") -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        fileStore.seed(cfgPath, text: #"{"tokens":{"refresh_token":"\#(refreshToken)"}}"#)
        return fileStore
    }

    private func provider(
        fileStore: FileStore, httpClient: HTTPClient, dateProvider: DateProvider = FixedDateProvider()
    ) -> FirebaseToolsTokenProvider {
        FirebaseToolsTokenProvider(fileStore: fileStore, httpClient: httpClient, configPath: cfgPath, dateProvider: dateProvider)
    }

    private func reply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        FakeHTTPClient.response(FirebaseToolsTokenProvider.tokenEndpoint, status: status, body: Data(body.utf8))
    }

    private func tokenReply(_ token: String, expiresIn: Int? = 3599) -> (Data, HTTPURLResponse) {
        let lifetime = expiresIn.map { #","expires_in":\#($0)"# } ?? ""
        return reply(200, #"{"access_token":"\#(token)","token_type":"Bearer"\#(lifetime)}"#)
    }

    @Test("missing config throws firebaseLoginRequired")
    func missingConfig() async {
        let p = provider(fileStore: InMemoryFileStore(), httpClient: FakeHTTPClient())
        await #expect(throws: AccessTokenError.firebaseLoginRequired) {
            _ = try await p.token()
        }
    }

    @Test("config without a refresh token throws firebaseLoginRequired")
    func configWithoutRefreshToken() async {
        let fileStore = InMemoryFileStore()
        fileStore.seed(cfgPath, text: #"{"tokens":{}}"#)
        let p = provider(fileStore: fileStore, httpClient: FakeHTTPClient())
        await #expect(throws: AccessTokenError.firebaseLoginRequired) {
            _ = try await p.token()
        }
    }

    @Test("isFirebaseLoggedIn detects refresh_token")
    func detection() {
        let p = provider(fileStore: seededFileStore(), httpClient: FakeHTTPClient())
        #expect(p.isFirebaseLoggedIn() == true)
    }

    @Test("default config path honors XDG_CONFIG_HOME, else $HOME/.config")
    func configPath() {
        #expect(
            FirebaseToolsTokenProvider.defaultConfigPath(environment: ["XDG_CONFIG_HOME": "/xdg"])
                == "/xdg/configstore/firebase-tools.json")
        #expect(
            FirebaseToolsTokenProvider.defaultConfigPath(environment: ["XDG_CONFIG_HOME": "  "])
                == "\(HomeDirectoryLocator.path)/.config/configstore/firebase-tools.json")
    }

    @Test("token request body is a strictly encoded form")
    func formBody() async throws {
        let httpClient = FakeHTTPClient { _ in self.tokenReply("ya29.x") }
        _ = try await provider(fileStore: seededFileStore(refreshToken: "1//a+b&c=d%e"), httpClient: httpClient).token()
        let request = try #require(httpClient.requests.first)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(request.httpMethod == "POST")
        #expect(body.contains("refresh_token=1%2F%2Fa%2Bb%26c%3Dd%25e"))
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.split(separator: "&").count == 4)
    }

    @Test("token reuses the cached access token until it is rejected")
    func tokenReusesCachedAccessToken() async throws {
        let exchanges = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in self.tokenReply("T\(exchanges.next())") }
        let p = provider(fileStore: seededFileStore(), httpClient: httpClient)

        let first = try await p.token()
        let second = try await p.token()
        let refreshed = try await p.forceRefresh(rejecting: first)

        #expect(first == "T1")
        #expect(second == "T1")
        #expect(refreshed == "T2")
        #expect(try await p.token() == "T2")
        #expect(exchanges.value == 2)
    }

    @Test("forceRefresh for a token that was already replaced returns the replacement without exchanging")
    func forceRefreshOfStaleRejection() async throws {
        let exchanges = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in self.tokenReply("T\(exchanges.next())") }
        let p = provider(fileStore: seededFileStore(), httpClient: httpClient)

        let first = try await p.token()
        let second = try await p.forceRefresh(rejecting: first)
        let late = try await p.forceRefresh(rejecting: first)

        #expect(second == "T2")
        #expect(late == "T2")
        #expect(exchanges.value == 2)
    }

    @Test("an expired cached token is exchanged again; a live one is not")
    func expiryUsesInjectedClock() async throws {
        let dateProvider = FixedDateProvider()
        let exchanges = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in self.tokenReply("T\(exchanges.next())", expiresIn: 3600) }
        let p = provider(fileStore: seededFileStore(), httpClient: httpClient, dateProvider: dateProvider)

        _ = try await p.token()
        dateProvider.advance(by: 3_000)
        #expect(try await p.token() == "T1")
        dateProvider.advance(by: 541)  // 3541s > 3600 - 60s skew
        #expect(try await p.token() == "T2")
        #expect(exchanges.value == 2)
    }

    @Test("a short-lived token is still reused, not exchanged per request")
    func shortLivedTokenIsCached() async throws {
        let dateProvider = FixedDateProvider()
        let exchanges = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in self.tokenReply("T\(exchanges.next())", expiresIn: 30) }
        let p = provider(fileStore: seededFileStore(), httpClient: httpClient, dateProvider: dateProvider)

        _ = try await p.token()
        _ = try await p.token()
        #expect(exchanges.value == 1)
        dateProvider.advance(by: 16)
        _ = try await p.token()
        #expect(exchanges.value == 2)
    }

    @Test("cache lifetime: skew for normal tokens, half for short ones, default when absent or bogus")
    func cacheLifetimeTable() {
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: 3599) == 3539)
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: 120) == 60)
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: 30) == 15)
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: nil) == 3540)
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: 0) == 3540)
        #expect(FirebaseToolsTokenProvider.cacheLifetime(expiresIn: -5) == 3540)
    }

    @Test("concurrent force refreshes share one exchange and none is cancelled")
    func concurrentForceRefreshShares() async throws {
        let exchanges = AtomicCounter()
        let httpClient = FakeHTTPClient { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return self.tokenReply("T\(exchanges.next())")
        }
        let p = provider(fileStore: seededFileStore(), httpClient: httpClient)
        let first = try await p.token()

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<6 { group.addTask { try await p.forceRefresh(rejecting: first) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results == Array(repeating: "T2", count: 6))
        #expect(exchanges.value == 2)
    }

    @Test("invalid_grant surfaces refreshTokenInvalid with Google's description")
    func invalidGrant() async {
        let httpClient = FakeHTTPClient { _ in
            self.reply(400, #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)
        }
        await #expect(throws: AccessTokenError.refreshTokenInvalid("Token has been expired or revoked.")) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: httpClient).token()
        }
    }

    @Test("other token endpoint failures are tokenExchangeFailed with the status and description")
    func otherFailures() async {
        let httpClient = FakeHTTPClient { _ in
            self.reply(400, #"{"error":"invalid_client","error_description":"The OAuth client was deleted."}"#)
        }
        await #expect(throws: AccessTokenError.tokenExchangeFailed("status 400: The OAuth client was deleted.")) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: httpClient).token()
        }
        let unavailable = FakeHTTPClient { _ in self.reply(503, "<html>upstream down</html>") }
        await #expect(throws: AccessTokenError.tokenExchangeFailed("status 503: <html>upstream down</html>")) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: unavailable).token()
        }
    }

    @Test("an undecodable success response is tokenExchangeFailed")
    func undecodableResponse() async {
        let httpClient = FakeHTTPClient { _ in self.reply(200, #"{"token_type":"Bearer"}"#) }
        await #expect(throws: AccessTokenError.tokenExchangeFailed("the token response was not understood.")) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: httpClient).token()
        }
    }

    @Test("a transport failure is a network error, not an auth failure")
    func transportFailure() async {
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.transport("The Internet connection appears to be offline.") }
        await #expect(throws: CrashlyticsClientError.network("The Internet connection appears to be offline.")) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: httpClient).token()
        }
    }

    @Test("a cancelled transport call surfaces as CancellationError")
    func cancelledTransport() async {
        let httpClient = FakeHTTPClient { _ in throw HTTPTransportError.cancelled }
        await #expect(throws: CancellationError.self) {
            _ = try await self.provider(fileStore: self.seededFileStore(), httpClient: httpClient).token()
        }
    }
}
