import Foundation

enum AccessTokenError: Error, Equatable, Sendable {
    case firebaseLoginRequired
    case refreshTokenInvalid(String)
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
        case .refreshTokenInvalid(let reason):
            return "Stored refresh token is invalid (\(reason)). Re-run: firebase login --reauth"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        }
    }
}
