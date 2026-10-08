import Foundation

struct FirebaseToolsLoginProbe: FirebaseLoginProbe {
    let subprocessExecutor: SubprocessExecutor
    let tokens: FirebaseToolsTokenProvider

    func isCLIInstalled() -> Bool {
        (try? subprocessExecutor.execute(
            executable: "/usr/bin/env", arguments: ["which", "firebase"], standardInput: nil))?.exitCode == 0
    }

    func hasStoredLogin() -> Bool { tokens.isFirebaseLoggedIn() }

    func verifyAccessToken() async throws { _ = try await tokens.token() }
}
