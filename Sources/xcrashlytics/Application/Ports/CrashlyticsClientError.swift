import Foundation

/// Messages are human sentences, never raw response bodies or Swift enum dumps.
enum CrashlyticsClientError: Error, Equatable, Sendable {
    case network(String)
    /// 401 even after a token refresh: Google rejects the account's token.
    case unauthorized(String)
    /// 403: the signed-in account cannot read this Firebase app.
    case permissionDenied(String)
    /// 404: the app, issue, or event does not exist.
    case notFound(String)
    case apiError(code: Int, message: String)
    case rateLimited(retries: Int)
    case decodingFailed(String)
    case invalidRequest(String)
}
