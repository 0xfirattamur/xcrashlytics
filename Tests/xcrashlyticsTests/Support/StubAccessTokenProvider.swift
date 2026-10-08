import Foundation
@testable import xcrashlytics

/// `AccessTokenProvider` test double. `token()` serves the first token;
/// each `forceRefresh` advances to the next one (the last repeats).
final class StubAccessTokenProvider: AccessTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String]
    private var current = 0
    private var rejections: [String] = []

    init(tokens: [String] = ["AT"]) {
        self.tokens = tokens
    }

    /// Tokens the client reported as rejected, in order.
    var rejectedTokens: [String] { lock.withLock { rejections } }

    func token() async throws -> String {
        lock.withLock { tokens[current] }
    }

    func forceRefresh(rejecting token: String) async throws -> String {
        lock.withLock {
            rejections.append(token)
            current = min(current + 1, tokens.count - 1)
            return tokens[current]
        }
    }
}
