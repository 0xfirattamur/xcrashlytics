import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("error contract")
struct FailureContractTests {
    @Test("unknown errors map to INTERNAL / exit 1")
    func internalError() {
        struct Mystery: Error {}
        let failure = CommandRunner.failure(for: Mystery())
        #expect(failure.code == "INTERNAL")
        #expect(failure.exitCode == 1)
    }

    @Test("commandRunner does not wrap an ExitCode a command threw itself")
    func commandRunnerKeepsExplicitExit() async {
        let console = SpyConsole()
        await #expect(throws: ExitCode(1)) {
            try await CommandRunner(console: console).run(format: .json) {
                throw ExitCode(1)
            }
        }
        #expect(console.outputs.isEmpty && console.diagnosticWrites.isEmpty)
    }

    @Test("INTERNAL messages are human sentences, not NSError dumps")
    func internalMessageIsLocalizedDescription() {
        let nsError = NSError(
            domain: NSCocoaErrorDomain, code: 513,
            userInfo: [NSLocalizedDescriptionKey: "You don’t have permission."])
        let failure = CommandRunner.failure(for: nsError)
        #expect(failure.code == "INTERNAL")
        #expect(failure.message == "You don’t have permission.")
        #expect(!failure.message.contains("Error Domain"))
        #expect(!failure.message.contains("UserInfo"))
    }

    @Test("a failed config write is INTERNAL and names the config, never the tmp file")
    func fileStoreErrorMessage() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain, code: 513,
            userInfo: [NSLocalizedFailureReasonErrorKey: "You don’t have permission."])
        let failure = CommandRunner.failure(
            for: FileStoreError(path: "/repo/.xcrashlytics.json", underlying: underlying))
        #expect(failure.code == "INTERNAL")
        #expect(failure.message == "could not write /repo/.xcrashlytics.json: You don’t have permission.")
        #expect(!failure.message.contains(".tmp-"))
    }

    /// Every error the app can raise, with the (code, exit) agents rely on.
    private struct ContractCase {
        var label: String
        var error: any Error
        var code: String
        var exit: Int32

        init(_ label: String, _ error: any Error, _ code: String, _ exit: Int32) {
            self.label = label
            self.error = error
            self.code = code
            self.exit = exit
        }
    }

    private static let contract: [ContractCase] = [
        ContractCase("firebaseLoginRequired", AccessTokenError.firebaseLoginRequired, "AUTH_REQUIRED", 2),
        ContractCase("refreshTokenInvalid", AccessTokenError.refreshTokenInvalid("invalid_grant"), "AUTH_EXPIRED", 2),
        ContractCase("unauthorized", CrashlyticsClientError.unauthorized("token rejected"), "AUTH_EXPIRED", 2),
        ContractCase("permissionDenied", CrashlyticsClientError.permissionDenied("no access"), "PERMISSION_DENIED", 2),
        ContractCase("rateLimited", CrashlyticsClientError.rateLimited(retries: 3), "RATE_LIMITED", 3),
        ContractCase("missingAppId", ConfigError.missingAppId, "CONFIG_MISSING", 4),
        ContractCase("missingBundleId", ConfigError.missingBundleId(profile: "p"), "CONFIG_MISSING", 4),
        ContractCase("invalidFile", ConfigError.invalidFile, "CONFIG_INVALID", 4),
        ContractCase("invalidAppId", ConfigError.invalidAppId("nope"), "CONFIG_INVALID", 4),
        ContractCase("invalidRequest", CrashlyticsClientError.invalidRequest("bad id"), "BAD_INPUT", 5),
        ContractCase("since", SinceExpressionError.invalid("7x"), "BAD_INPUT", 5),
        ContractCase("invalidInput", InvalidInputError("bad value"), "BAD_INPUT", 5),
        ContractCase("validation", ValidationError("bad flag"), "BAD_INPUT", 5),
        ContractCase("notFound", CrashlyticsClientError.notFound("no such issue"), "NOT_FOUND", 5),
        ContractCase("tokenExchangeFailed", AccessTokenError.tokenExchangeFailed("503"), "API_ERROR", 6),
        ContractCase("apiError", CrashlyticsClientError.apiError(code: 500, message: "boom"), "API_ERROR", 6),
        ContractCase("decodingFailed", CrashlyticsClientError.decodingFailed("missing key"), "API_ERROR", 6),
        ContractCase("network", CrashlyticsClientError.network("offline"), "NETWORK_ERROR", 7),
    ]

    @Test("every error maps to its documented code and exit code, with a human message")
    func fullContractTable() {
        for entry in Self.contract {
            let failure = CommandRunner.failure(for: entry.error)
            #expect(failure.code == entry.code, "\(entry.label) code")
            #expect(failure.exitCode == entry.exit, "\(entry.label) exit")
            #expect(!failure.message.isEmpty, "\(entry.label) message")
            #expect(!failure.message.contains("Error Domain"), "\(entry.label) message")
            #expect(!failure.message.contains("CrashlyticsClientError"), "\(entry.label) leaks enum name")
        }
    }

    @Test("messages carry the underlying detail and the actionable hint")
    func messagesAndHints() {
        func failure(_ error: Error) -> CommandFailure { CommandRunner.failure(for: error) }
        #expect(failure(CrashlyticsClientError.permissionDenied("no access")).message.contains("no access"))
        #expect(failure(CrashlyticsClientError.permissionDenied("x")).hint?.contains("xcrashlytics use") == true)
        #expect(failure(CrashlyticsClientError.notFound("no such issue")).message == "no such issue")
        #expect(failure(CrashlyticsClientError.network("offline")).message.contains("offline"))
        #expect(failure(CrashlyticsClientError.network("offline")).hint != nil)
        #expect(failure(CrashlyticsClientError.apiError(code: 502, message: "Bad gateway")).message == "Firebase API error 502: Bad gateway")
        #expect(failure(CrashlyticsClientError.rateLimited(retries: 4)).message.contains("4"))
        #expect(failure(AccessTokenError.tokenExchangeFailed("503")).hint == "Usually transient; retry.")
        #expect(failure(CrashlyticsClientError.unauthorized("x")).hint == "Run: firebase login --reauth")
        #expect(failure(ConfigError.invalidFile).hint?.contains(".xcrashlytics.json") == true)
        #expect(failure(ConfigError.invalidAppId("nope")).message.contains("'nope'"))
    }

    @Test("missingBundleId maps to CONFIG_MISSING with a re-run hint")
    func missingBundleIdMapping() {
        let failure = CommandRunner.failure(for: ConfigError.missingBundleId(profile: "staging"))
        #expect(failure.code == "CONFIG_MISSING")
        #expect(failure.exitCode == 4)
        #expect(failure.message == "profile 'staging' has no bundle id.")
        #expect(failure.hint == "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile staging --bundle-id <BUNDLE_ID>")
    }

    @Test("missingBundleId without a profile uses generic wording")
    func missingBundleIdNoProfile() {
        let failure = CommandRunner.failure(for: ConfigError.missingBundleId(profile: nil))
        #expect(failure.code == "CONFIG_MISSING")
        #expect(failure.exitCode == 4)
        #expect(failure.message == "no bundle id configured.")
        #expect(failure.hint == "Run: xcrashlytics init --app-id <GOOGLE_APP_ID> --profile <profile> --bundle-id <BUNDLE_ID>")
    }
}
