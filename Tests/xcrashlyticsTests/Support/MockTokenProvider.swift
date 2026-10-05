import Foundation
@testable import xcrashlytics

/// `AccessTokenProvider` test double.
final class MockTokenProvider: AccessTokenProvider, @unchecked Sendable {
    private(set) var tokenCalls = 0
    private(set) var forceRefreshCalls = 0
    var nextTokens: [String]

    init(tokens: [String] = ["AT"]) {
        self.nextTokens = tokens
    }

    func token() async throws -> String {
        tokenCalls += 1
        if nextTokens.count > 1 {
            return nextTokens.removeFirst()
        }
        return nextTokens.first ?? "AT"
    }

    func forceRefresh() async throws -> String {
        forceRefreshCalls += 1
        if nextTokens.count > 1 {
            return nextTokens.removeFirst()
        }
        return nextTokens.first ?? "AT"
    }
}
