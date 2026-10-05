//
//  AccessTokenProvider.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Errors raised by an `AccessTokenProvider`.
enum AccessTokenError: Error, Equatable, Sendable {
    /// firebase-tools config file not found — user hasn't run `firebase login`.
    case firebaseLoginRequired
    /// Refresh token has been revoked / expired — needs another `firebase login`.
    case refreshTokenInvalid(String)
    /// Token endpoint returned an unexpected failure.
    case tokenExchangeFailed(String)
}

extension AccessTokenError: CustomStringConvertible {
    var description: String {
        switch self {
        case .firebaseLoginRequired:
            return """
            firebase CLI is not authenticated.

            One-time setup:
                npm install -g firebase-tools   # or: brew install firebase-cli
                firebase login

            xcrashlytics then reads the refresh token firebase-tools stored.
            """
        case .refreshTokenInvalid(let detail):
            return "Stored refresh token is invalid (\(detail)). Re-run: firebase login --reauth"
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        }
    }
}

/// Source of a Google access token. Backed by the Firebase CLI's stored
/// refresh token (`~/.config/configstore/firebase-tools.json`).
protocol AccessTokenProvider: Sendable {
    /// Returns a non-expired access token. May internally refresh.
    func token() async throws -> String
    /// Forces a fresh exchange even if cached looks valid. Used on 401.
    func forceRefresh() async throws -> String
}

/// `AccessTokenProvider` that piggybacks on `firebase login`.
///
/// Mechanism:
/// 1. User runs `firebase login` once — Firebase CLI writes a refresh token to
///    `~/.config/configstore/firebase-tools.json`.
/// 2. This provider reads that refresh token and exchanges it at Google's
///    OAuth token endpoint using firebase-tools' built-in `(client_id, client_secret)`.
/// 3. The returned access token carries firebase-tools' Cloud Platform scope,
///    which the Firebase Crashlytics API accepts. No per-project API
///    enablement required.
///
/// `clientId` and `clientSecret` are the public OAuth credentials bundled with
/// firebase-tools. The user's refresh token is the secret; it is sent only to
/// `tokenEndpoint`.
struct FirebaseToolsTokenProvider: AccessTokenProvider {
    static let clientId = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
    static let clientSecret = "j9iVZfS8kkCEFUPaAeJV0sAi"
    static let tokenEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/token")!

    let configPath: String
    private let fs: FileSystem
    private let httpTransport: HTTPTransport
    private let cache: FirebaseAccessTokenCache

    init(
        fs: FileSystem,
        httpTransport: HTTPTransport,
        configPath: String? = nil
    ) {
        self.fs = fs
        self.httpTransport = httpTransport
        let home = NSString(string: "~").expandingTildeInPath
        self.configPath = configPath ?? "\(home)/.config/configstore/firebase-tools.json"
        self.cache = FirebaseAccessTokenCache()
    }

    func token() async throws -> String {
        try await cache.token(now: Date()) {
            try await exchange()
        }
    }

    func forceRefresh() async throws -> String {
        try await cache.forceRefresh(now: Date()) {
            try await exchange()
        }
    }

    /// `true` if the firebase-tools config file exists at the expected path.
    func isFirebaseLoggedIn() -> Bool {
        guard fs.fileExists(at: configPath),
              let data = try? fs.read(at: configPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let tokens = obj["tokens"] as? [String: Any]
        return tokens?["refresh_token"] is String
    }

    // MARK: - Internal

    func readRefreshToken() throws -> String {
        guard fs.fileExists(at: configPath) else {
            throw AccessTokenError.firebaseLoginRequired
        }
        let data: Data
        do {
            data = try fs.read(at: configPath)
        } catch {
            throw AccessTokenError.firebaseLoginRequired
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let refresh = tokens["refresh_token"] as? String,
              !refresh.isEmpty
        else {
            throw AccessTokenError.firebaseLoginRequired
        }
        return refresh
    }

    private func exchange() async throws -> CachedAccessToken {
        let refresh = try readRefreshToken()

        var req = URLRequest(url: Self.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "refresh_token": refresh,
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "grant_type": "refresh_token"
        ]
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await httpTransport.send(req)
        } catch {
            throw AccessTokenError.tokenExchangeFailed("\(error)")
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") {
                throw AccessTokenError.refreshTokenInvalid(body)
            }
            throw AccessTokenError.tokenExchangeFailed("status \(response.statusCode): \(body)")
        }

        struct Response: Decodable {
            let accessToken: String
            let expiresIn: Int?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AccessTokenError.tokenExchangeFailed("decoding: \(error)")
        }
        let lifetime = TimeInterval(decoded.expiresIn ?? 3_600)
        let expiresAt = Date().addingTimeInterval(max(0, lifetime - 60))
        return CachedAccessToken(value: decoded.accessToken, expiresAt: expiresAt)
    }
}

private struct CachedAccessToken: Sendable {
    var value: String
    var expiresAt: Date

    func isValid(now: Date) -> Bool {
        expiresAt > now
    }
}

private actor FirebaseAccessTokenCache {
    private var cached: CachedAccessToken?
    private var refreshTask: Task<CachedAccessToken, Error>?

    func token(
        now: Date,
        refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        if let cached, cached.isValid(now: now) {
            return cached.value
        }
        return try await refreshAndStore(refresh)
    }

    func forceRefresh(
        now _: Date,
        refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        cached = nil
        refreshTask?.cancel()
        refreshTask = nil
        return try await refreshAndStore(refresh)
    }

    private func refreshAndStore(
        _ refresh: @Sendable @escaping () async throws -> CachedAccessToken
    ) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value.value
        }
        let task = Task {
            try await refresh()
        }
        refreshTask = task
        do {
            let token = try await task.value
            cached = token
            refreshTask = nil
            return token.value
        } catch {
            refreshTask = nil
            throw error
        }
    }
}
