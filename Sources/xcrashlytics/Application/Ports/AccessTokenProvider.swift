import Foundation

/// Google access tokens, backed by the refresh token firebase-tools stores.
protocol AccessTokenProvider: Sendable {
    /// A non-expired token; refreshes internally when needed.
    func token() async throws -> String
    /// Called after a 401 on `token`. Returns a different token: one another caller already
    /// refreshed to, or a fresh exchange that concurrent callers share.
    func forceRefresh(rejecting token: String) async throws -> String
}
