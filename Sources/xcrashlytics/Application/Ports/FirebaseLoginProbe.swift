/// What `init` needs to know about the machine's firebase-tools setup.
protocol FirebaseLoginProbe: Sendable {
    func isCLIInstalled() -> Bool
    func hasStoredLogin() -> Bool
    /// Exchanges the stored refresh token; throws what `AccessTokenProvider.token()` throws.
    func verifyAccessToken() async throws
}
