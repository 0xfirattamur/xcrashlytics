import Foundation

/// Codes and exit codes are frozen: additions only.
enum FailureMapper {
    private enum ExitStatus {
        static let authentication: Int32 = 2
        static let rateLimited: Int32 = 3
        static let configuration: Int32 = 4
        static let badInput: Int32 = 5
        static let apiError: Int32 = 6
        static let network: Int32 = 7
        static let internalError: Int32 = 1
    }

    // MARK: - Public API

    /// The first matching group wins.
    static func failure(for error: Error) -> CommandFailure {
        authFailure(for: error)
            ?? configFailure(for: error)
            ?? inputFailure(for: error)
            ?? apiFailure(for: error)
            ?? CommandFailure(
                code: "INTERNAL", exitCode: ExitStatus.internalError, message: error.localizedDescription, hint: nil)
    }

    // MARK: - Authentication

    private static func authFailure(for error: Error) -> CommandFailure? {
        switch error {
        case AccessTokenError.firebaseLoginRequired:
            return authentication(
                "AUTH_REQUIRED", "firebase CLI is not authenticated.", hint: "Run: firebase login")
        case let AccessTokenError.refreshTokenInvalid(reason):
            return authentication(
                "AUTH_EXPIRED", "Stored refresh token is invalid (\(reason)).", hint: "Run: firebase login --reauth")
        case let CrashlyticsClientError.unauthorized(reason):
            return authentication(
                "AUTH_EXPIRED",
                "Google rejected the signed-in account's token: \(reason)",
                hint: "Run: firebase login --reauth")
        case let CrashlyticsClientError.permissionDenied(reason):
            return authentication(
                "PERMISSION_DENIED",
                "The signed-in Firebase account cannot read this app: \(reason)",
                hint: "Check the account with: firebase login:list, "
                    + "or select another profile with: xcrashlytics use <profile>")
        case let CrashlyticsClientError.rateLimited(retries):
            return CommandFailure(
                code: "RATE_LIMITED",
                exitCode: ExitStatus.rateLimited,
                message: "Firebase API rate limit hit after \(retries) retries.",
                hint: "Wait and retry, or lower --concurrency.")
        default:
            return nil
        }
    }

    private static func authentication(_ code: String, _ message: String, hint: String) -> CommandFailure {
        CommandFailure(code: code, exitCode: ExitStatus.authentication, message: message, hint: hint)
    }

    // MARK: - Configuration

    private static func configFailure(for error: Error) -> CommandFailure? {
        switch error {
        case ConfigError.missingAppId:
            return configuration(
                "CONFIG_MISSING",
                "no appId configured.",
                hint: "Run: xcrashlytics init --app-id <GOOGLE_APP_ID>, or: xcrashlytics use <profile>")
        case let ConfigError.missingBundleId(profile):
            let message = profile.map { "profile '\($0)' has no bundle id." } ?? "no bundle id configured."
            return configuration(
                "CONFIG_MISSING",
                message,
                hint: "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile \(profile ?? "<profile>") "
                    + "--bundle-id <BUNDLE_ID>")
        case ConfigError.invalidFile:
            return configuration(
                "CONFIG_INVALID",
                "the .xcrashlytics.json file is invalid.",
                hint: "Fix the JSON in .xcrashlytics.json, or delete it and run: xcrashlytics init --scan")
        case let ConfigError.invalidAppId(appId):
            return configuration(
                "CONFIG_INVALID",
                "app id '\(appId)' is not a Firebase app id (expected 1:<project-number>:<platform>:<hash>).",
                hint: "Copy GOOGLE_APP_ID from GoogleService-Info.plist, then run xcrashlytics init.")
        default:
            return nil
        }
    }

    private static func configuration(_ code: String, _ message: String, hint: String) -> CommandFailure {
        CommandFailure(code: code, exitCode: ExitStatus.configuration, message: message, hint: hint)
    }

    // MARK: - Bad input

    private static func inputFailure(for error: Error) -> CommandFailure? {
        switch error {
        case let CrashlyticsClientError.invalidRequest(reason):
            return badInput(reason)
        case let CrashlyticsClientError.notFound(reason):
            return CommandFailure(
                code: "NOT_FOUND",
                exitCode: ExitStatus.badInput,
                message: reason,
                hint: "Check the id, or list ids with: xcrashlytics issues --format json")
        case let error as SinceExpressionError:
            return badInput(error.localizedDescription)
        case let error as InvalidInputError:
            return badInput(error.message)
        default:
            return nil
        }
    }

    private static func badInput(_ message: String) -> CommandFailure {
        CommandFailure(code: "BAD_INPUT", exitCode: ExitStatus.badInput, message: message, hint: nil)
    }

    // MARK: - Remote API

    private static func apiFailure(for error: Error) -> CommandFailure? {
        switch error {
        case let CrashlyticsClientError.network(reason):
            return CommandFailure(
                code: "NETWORK_ERROR",
                exitCode: ExitStatus.network,
                message: "Could not reach Google: \(reason)",
                hint: "Check the network connection, then retry.")
        case let AccessTokenError.tokenExchangeFailed(reason):
            return transientApiError("Google's token service failed: \(reason)")
        case let CrashlyticsClientError.apiError(code, message):
            return transientApiError("Firebase API error \(code): \(message)")
        case let CrashlyticsClientError.decodingFailed(reason):
            return CommandFailure(
                code: "API_ERROR",
                exitCode: ExitStatus.apiError,
                message: "Firebase response decoding failed: \(reason)",
                hint: nil)
        default:
            return nil
        }
    }

    private static func transientApiError(_ message: String) -> CommandFailure {
        CommandFailure(
            code: "API_ERROR", exitCode: ExitStatus.apiError, message: message, hint: "Usually transient; retry.")
    }
}
