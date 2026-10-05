import ArgumentParser
import Testing
@testable import xcrashlytics

@Suite("error contract")
struct ErrorContractTests {
    @Test("missing firebase login maps to AUTH_REQUIRED / exit 2")
    func authRequired() {
        let failure = ErrorContract.failure(for: AccessTokenError.firebaseLoginRequired)
        #expect(failure.code == "AUTH_REQUIRED")
        #expect(failure.exitCode == 2)
        #expect(failure.hint == "Run: firebase login")
    }

    @Test("invalid refresh token maps to AUTH_EXPIRED / exit 2")
    func authExpired() {
        let failure = ErrorContract.failure(for: AccessTokenError.refreshTokenInvalid("revoked"))
        #expect(failure.code == "AUTH_EXPIRED")
        #expect(failure.exitCode == 2)
        #expect(failure.hint == "Run: firebase login --reauth")
    }

    @Test("rate limit maps to RATE_LIMITED / exit 3")
    func rateLimited() {
        let failure = ErrorContract.failure(for: FirebaseError.rateLimited(retries: 5))
        #expect(failure.code == "RATE_LIMITED")
        #expect(failure.exitCode == 3)
    }

    @Test("missing appId maps to CONFIG_MISSING / exit 4")
    func configMissing() {
        let failure = ErrorContract.failure(for: ConfigError.missingAppId)
        #expect(failure.code == "CONFIG_MISSING")
        #expect(failure.exitCode == 4)
        #expect(failure.hint?.contains("xcrashlytics init") == true)
    }

    @Test("invalid request maps to BAD_INPUT / exit 5")
    func badInput() {
        let failure = ErrorContract.failure(for: FirebaseError.invalidRequest("issue id 'a b' contains unsupported characters."))
        #expect(failure.code == "BAD_INPUT")
        #expect(failure.exitCode == 5)
    }

    @Test("runtime ValidationError maps to BAD_INPUT / exit 5")
    func validationError() {
        let failure = ErrorContract.failure(for: ValidationError("provide an issue id argument or --issues FB-a,FB-b."))
        #expect(failure.code == "BAD_INPUT")
        #expect(failure.exitCode == 5)
    }

    @Test("API error maps to API_ERROR / exit 6")
    func apiError() {
        let failure = ErrorContract.failure(for: FirebaseError.apiError(code: 500, message: "boom"))
        #expect(failure.code == "API_ERROR")
        #expect(failure.exitCode == 6)
        #expect(failure.message.contains("500"))
    }

    @Test("decoding failure maps to API_ERROR / exit 6")
    func decodingFailure() {
        let failure = ErrorContract.failure(for: FirebaseError.decodingFailed("events: missing key"))
        #expect(failure.code == "API_ERROR")
        #expect(failure.exitCode == 6)
    }

    @Test("unknown errors map to INTERNAL / exit 1")
    func internalError() {
        struct Mystery: Error {}
        let failure = ErrorContract.failure(for: Mystery())
        #expect(failure.code == "INTERNAL")
        #expect(failure.exitCode == 1)
    }

    @Test("json body wraps failure in versioned error object with trailing newline")
    func jsonBody() throws {
        let body = try ErrorContract.jsonBody(
            CommandFailure(code: "API_ERROR", exitCode: 6, message: "boom", hint: nil))
        let root = try JSON.parse(body)
        #expect(root["schemaVersion"]?.int == 1)
        #expect(root["data"] == nil)
        let error = try #require(root["error"]?.object)
        #expect(error["code"]?.string == "API_ERROR")
        #expect(error["message"]?.string == "boom")
        #expect(error["hint"] == nil)
        #expect(body.hasSuffix("\n"))
        #expect(!body.hasSuffix("\n\n"))
    }

    @Test("json body includes hint when present")
    func jsonBodyWithHint() throws {
        let body = try ErrorContract.jsonBody(
            CommandFailure(code: "AUTH_REQUIRED", exitCode: 2, message: "not authenticated", hint: "Run: firebase login"))
        let root = try JSON.parse(body)
        #expect(root["schemaVersion"]?.int == 1)
        #expect(root["error"]?["hint"]?.string == "Run: firebase login")
    }

    @Test("text body is error line plus hint line")
    func textBody() {
        let body = ErrorContract.textBody(
            CommandFailure(code: "AUTH_REQUIRED", exitCode: 2, message: "not authenticated", hint: "Run: firebase login"))
        #expect(body == "error: not authenticated\nhint: Run: firebase login\n")
    }

    @Test("reportingFailures rethrows ExitCode with the mapped code")
    func reportingFailuresExitCode() async {
        await #expect(throws: ExitCode(4)) {
            try await IssuesCommand.parse([]).reportingFailures(jsonOutput: true) {
                throw ConfigError.missingAppId
            }
        }
    }

    @Test("reportingFailures passes successful bodies through")
    func reportingFailuresSuccess() async throws {
        try await IssuesCommand.parse([]).reportingFailures(jsonOutput: false) {
            "ok"
        }
    }

    @Test("missingBundleId maps to CONFIG_MISSING with a re-run hint")
    func missingBundleIdMapping() {
        let failure = ErrorContract.failure(for: ConfigError.missingBundleId(profile: "staging"))
        #expect(failure.code == "CONFIG_MISSING")
        #expect(failure.exitCode == 4)
        #expect(failure.message == "profile 'staging' has no bundle id.")
        #expect(failure.hint == "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile staging --bundle-id <BUNDLE_ID>")
    }

    @Test("missingBundleId without a profile uses generic wording")
    func missingBundleIdNoProfile() {
        let failure = ErrorContract.failure(for: ConfigError.missingBundleId(profile: nil))
        #expect(failure.code == "CONFIG_MISSING")
        #expect(failure.exitCode == 4)
        #expect(failure.message == "no bundle id configured.")
        #expect(failure.hint == "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile <profile> --bundle-id <BUNDLE_ID>")
    }
}
