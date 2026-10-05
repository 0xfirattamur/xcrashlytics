import ArgumentParser
import Foundation

extension AsyncParsableCommand {
    /// Wraps a command body: on failure, emits the contract (JSON to stdout
    /// when the command was asked for JSON output, text to stderr otherwise)
    /// and exits with the mapped code. Every command's `run()` goes through
    /// this so a new command cannot skip the contract.
    func reportingFailures<T>(
        jsonOutput: Bool,
        _ body: () async throws -> T
    ) async throws {
        do {
            _ = try await body()
        } catch let exit as ExitCode {
            throw exit
        } catch let exit as CleanExit {
            throw exit
        } catch {
            let failure = ErrorContract.failure(for: error)
            if jsonOutput {
                let bodyText = (try? ErrorContract.jsonBody(failure))
                    ?? "{\"error\":{\"code\":\"\(failure.code)\"}}\n"
                StandardConsole().output(bodyText)
            } else {
                FileHandle.standardError.write(Data(ErrorContract.textBody(failure).utf8))
            }
            throw ExitCode(failure.exitCode)
        }
    }
}

/// One failure in the stable agent-facing error contract.
struct CommandFailure: Equatable {
    var code: String
    var exitCode: Int32
    var message: String
    var hint: String?
}

/// Maps every domain error to a stable (code, exit code, message, hint) tuple
/// and renders it for text or JSON output. Codes and exit codes are frozen
/// after release — additions only.
enum ErrorContract {
    /// Maps an error to its contract entry by trying each domain group in turn.
    /// Split into helpers so no single function exceeds the lint thresholds;
    /// the `??` chain preserves the original first-match ordering.
    static func failure(for error: Error) -> CommandFailure {
        authFailure(for: error)
            ?? configFailure(for: error)
            ?? inputFailure(for: error)
            ?? apiFailure(for: error)
            ?? CommandFailure(code: "INTERNAL", exitCode: 1, message: "\(error)", hint: nil)
    }

    /// Auth and rate-limit errors (exit codes 2 and 3).
    private static func authFailure(for error: Error) -> CommandFailure? {
        switch error {
        case AccessTokenError.firebaseLoginRequired, FirebaseError.notAuthenticated:
            return CommandFailure(
                code: "AUTH_REQUIRED",
                exitCode: 2,
                message: "firebase CLI is not authenticated.",
                hint: "Run: firebase login"
            )
        case let AccessTokenError.refreshTokenInvalid(detail):
            return CommandFailure(
                code: "AUTH_EXPIRED",
                exitCode: 2,
                message: "Stored refresh token is invalid (\(detail)).",
                hint: "Run: firebase login --reauth"
            )
        case let AccessTokenError.tokenExchangeFailed(detail):
            return CommandFailure(
                code: "AUTH_EXPIRED",
                exitCode: 2,
                message: "Token exchange failed: \(detail)",
                hint: "Run: firebase login --reauth"
            )
        case let FirebaseError.refreshFailed(detail):
            return CommandFailure(
                code: "AUTH_EXPIRED",
                exitCode: 2,
                message: "Token refresh failed: \(detail)",
                hint: "Run: firebase login --reauth"
            )
        case let FirebaseError.rateLimited(retries):
            return CommandFailure(
                code: "RATE_LIMITED",
                exitCode: 3,
                message: "Firebase API rate limit hit after \(retries) retries.",
                hint: "Wait and retry, or lower --concurrency."
            )
        default:
            return nil
        }
    }

    /// Configuration errors (exit code 4).
    private static func configFailure(for error: Error) -> CommandFailure? {
        switch error {
        case ConfigError.missingAppId:
            return CommandFailure(
                code: "CONFIG_MISSING",
                exitCode: 4,
                message: "no appId configured.",
                hint: "Run: xcrashlytics init --app-id <GOOGLE_APP_ID>, or: xcrashlytics use <profile>"
            )
        case let ConfigError.missingBundleId(profile):
            let name = profile ?? "<profile>"
            return CommandFailure(
                code: "CONFIG_MISSING",
                exitCode: 4,
                message: profile.map { "profile '\($0)' has no bundle id." } ?? "no bundle id configured.",
                hint: "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile \(name) --bundle-id <BUNDLE_ID>"
            )
        case ConfigError.invalidFile:
            return CommandFailure(
                code: "CONFIG_MISSING",
                exitCode: 4,
                message: "the .xcrashlytics.json file is invalid.",
                hint: "Fix or remove .xcrashlytics.json, then run xcrashlytics init."
            )
        default:
            return nil
        }
    }

    /// Bad-input errors (exit code 5).
    private static func inputFailure(for error: Error) -> CommandFailure? {
        switch error {
        case let FirebaseError.invalidRequest(detail):
            return CommandFailure(
                code: "BAD_INPUT",
                exitCode: 5,
                message: detail,
                hint: nil
            )
        case let SinceDurationError.invalid(value):
            return CommandFailure(
                code: "BAD_INPUT",
                exitCode: 5,
                message: "invalid --since '\(value)' — use 7d, 24h, 30m, or all.",
                hint: nil
            )
        case let error as ValidationError:
            return CommandFailure(
                code: "BAD_INPUT",
                exitCode: 5,
                message: error.message,
                hint: nil
            )
        default:
            return nil
        }
    }

    /// Firebase API errors (exit code 6).
    private static func apiFailure(for error: Error) -> CommandFailure? {
        switch error {
        case let FirebaseError.apiError(code, message):
            return CommandFailure(
                code: "API_ERROR",
                exitCode: 6,
                message: "Firebase API error \(code): \(message)",
                hint: nil
            )
        case let FirebaseError.decodingFailed(detail):
            return CommandFailure(
                code: "API_ERROR",
                exitCode: 6,
                message: "Firebase response decoding failed: \(detail)",
                hint: nil
            )
        default:
            return nil
        }
    }

    static func jsonBody(_ failure: CommandFailure) throws -> String {
        struct Payload: Encodable {
            struct Body: Encodable {
                var code: String
                var message: String
                var hint: String?
            }
            var schemaVersion = outputSchemaVersion
            var error: Body
        }
        return try PayloadEncoder.json(
            Payload(error: .init(code: failure.code, message: failure.message, hint: failure.hint)))
    }

    static func textBody(_ failure: CommandFailure) -> String {
        var lines = ["error: \(failure.message)"]
        if let hint = failure.hint {
            lines.append("hint: \(hint)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
