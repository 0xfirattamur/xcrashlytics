import Foundation

/// The client id and secret are firebase-tools' public OAuth credentials. The user's refresh
/// token is the secret; it is sent only to `tokenEndpoint`.
struct FirebaseToolsTokenProvider: AccessTokenProvider {
    static let clientId = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
    static let clientSecret = "j9iVZfS8kkCEFUPaAeJV0sAi"
    static let tokenEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/token")!

    static let expirySkew: TimeInterval = 60
    static let defaultLifetime: TimeInterval = 3_600

    // firebase-tools keeps its login in `$XDG_CONFIG_HOME` (default `~/.config`) `/configstore`.
    static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let configHome = environment["XDG_CONFIG_HOME"]?.trimmedNonEmpty ?? "\(HomeDirectoryLocator.path)/.config"
        return "\(configHome)/configstore/firebase-tools.json"
    }

    let configPath: String
    private let fileStore: FileStore
    private let httpClient: HTTPClient
    private let dateProvider: DateProvider
    private let cache: FirebaseAccessTokenCache

    init(
        fileStore: FileStore,
        httpClient: HTTPClient,
        configPath: String? = nil,
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.fileStore = fileStore
        self.httpClient = httpClient
        self.dateProvider = dateProvider
        self.configPath = configPath ?? Self.defaultConfigPath()
        self.cache = FirebaseAccessTokenCache()
    }

    // MARK: - AccessTokenProvider

    func token() async throws -> String {
        try await cache.token(now: dateProvider.currentDate()) {
            try await exchange()
        }
    }

    func forceRefresh(rejecting token: String) async throws -> String {
        try await cache.forceRefresh(rejecting: token, now: dateProvider.currentDate()) {
            try await exchange()
        }
    }

    func isFirebaseLoggedIn() -> Bool {
        guard let data = try? fileStore.readData(at: configPath) else { return false }
        return Self.storedRefreshToken(in: data) != nil
    }

    func readRefreshToken() throws -> String {
        guard fileStore.exists(at: configPath) else {
            throw AccessTokenError.firebaseLoginRequired
        }
        guard let data = try? fileStore.readData(at: configPath),
              let refreshToken = Self.storedRefreshToken(in: data),
              !refreshToken.isEmpty
        else {
            throw AccessTokenError.firebaseLoginRequired
        }
        return refreshToken
    }

    // Never less than half the lifetime, so a short-lived token is reused instead of re-exchanged on every request.
    static func cacheLifetime(expiresIn: Int?) -> TimeInterval {
        let lifetime = expiresIn.flatMap { $0 > 0 ? TimeInterval($0) : nil } ?? defaultLifetime
        return max(lifetime - expirySkew, lifetime / 2)
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: CrashlyticsDTO.FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private func exchange() async throws -> CachedAccessToken {
        let refreshToken = try readRefreshToken()
        let request = Self.tokenRequest(refreshToken: refreshToken)
        let (data, response) = try await send(request)

        guard (200..<300).contains(response.statusCode) else {
            throw Self.failure(status: response.statusCode, body: data)
        }
        let tokenResponse = try Self.decodeTokenResponse(data)
        let lifetime = Self.cacheLifetime(expiresIn: tokenResponse.expiresIn?.intValue)
        let expiresAt = dateProvider.currentDate().addingTimeInterval(lifetime)
        return CachedAccessToken(value: tokenResponse.accessToken, expiresAt: expiresAt)
    }

    private static func storedRefreshToken(in configData: Data) -> String? {
        let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let tokens = config?["tokens"] as? [String: Any]
        return tokens?["refresh_token"] as? String
    }

    private static func tokenRequest(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoder.body([
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ])
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await httpClient.send(request)
        } catch HTTPTransportError.cancelled {
            throw CancellationError()
        } catch let error as CancellationError {
            throw error
        } catch HTTPTransportError.transport(let message) {
            throw CrashlyticsClientError.network(message)
        } catch {
            throw CrashlyticsClientError.network(error.localizedDescription)
        }
    }

    private static func decodeTokenResponse(_ data: Data) throws -> TokenResponse {
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AccessTokenError.tokenExchangeFailed("the token response was not understood.")
        }
    }

    // `invalid_grant` means the stored login is revoked; anything else is a token service failure.
    private static func failure(status: Int, body: Data) -> AccessTokenError {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let code = (object?["error"] as? String)?.trimmedNonEmpty
        let description = (object?["error_description"] as? String)?.trimmedNonEmpty
        if code == "invalid_grant" {
            return .refreshTokenInvalid(description ?? "invalid_grant")
        }
        let reason = description ?? code
            ?? String(data: body, encoding: .utf8)?.trimmedNonEmpty.map { String($0.prefix(200)) }
            ?? "no response body"
        return .tokenExchangeFailed("status \(status): \(reason)")
    }
}

// MARK: - Token cache

private struct CachedAccessToken: Sendable {
    var value: String
    var expiresAt: Date

    func isValid(now: Date) -> Bool {
        expiresAt > now
    }
}

/// Concurrent callers share one in-flight exchange.
private actor FirebaseAccessTokenCache {
    private var cached: CachedAccessToken?
    private var inFlight: (id: Int, task: Task<CachedAccessToken, Error>)?
    private var nextExchangeId = 0

    func token(
        now: Date,
        refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        if let cached, cached.isValid(now: now) {
            return cached.value
        }
        return try await exchange(refresh)
    }

    // A different valid cached token means someone refreshed first; otherwise drop the rejected
    // token and exchange. An exchange in flight is joined, never cancelled.
    func forceRefresh(
        rejecting rejected: String,
        now: Date,
        refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        if let cached, cached.value != rejected, cached.isValid(now: now) {
            return cached.value
        }
        if cached?.value == rejected {
            cached = nil
        }
        return try await exchange(refresh)
    }

    private func exchange(
        _ refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        if let inFlight {
            return try await inFlight.task.value.value
        }
        nextExchangeId += 1
        let id = nextExchangeId
        let task = Task { try await refresh() }
        inFlight = (id, task)
        do {
            let token = try await task.value
            cached = token
            if inFlight?.id == id { inFlight = nil }
            return token.value
        } catch {
            if inFlight?.id == id { inFlight = nil }
            throw error
        }
    }
}
