import ArgumentParser
import Foundation

struct InitCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write .xcrashlytics.json in the current directory and verify the Firebase setup.",
        discussion: """
        Examples:
          xcrashlytics init --scan
          xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --bundle-id com.example.app
          xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --app-library KeyboardCore

        --scan finds every GoogleService-Info.plist and google-services.json
        under the current directory (skipping build outputs and vendored
        copies) and writes one profile per app, bundle id included. An app
        whose bundle id extends another's (com.x.app.widget) is named by the
        suffix and records `extensionOf`; the app itself is named `app`. It
        also records the repo's framework and static-library targets as
        `appLibraries`: Firebase labels them third-party, but their frames
        count as app frames (--app-frames-only). Re-scanning keeps the names
        of profiles the config already has.
        """
    )

    @Flag(name: .long, help: "Discover app ids, profiles, and bundle ids from Firebase config files in this directory.")
    var scan: Bool = false

    @Option(
        name: .long,
        help:
            "Firebase app id, any platform (GOOGLE_APP_ID from GoogleService-Info.plist / google-services.json)."
    )
    var appId: String?

    @Option(
        name: .long,
        help: "Named environment profile to create and activate, for example staging or release."
    )
    var profile: String?

    @Option(
        name: .long,
        help: """
            App bundle id — scopes Xcode Organizer crash scanning \
            to ~/Library/Developer/Xcode/Products/<bundle-id>.
            """
    )
    var bundleId: String?

    @Option(
        name: .customLong("app-library"),
        help: """
            First-party framework or library (e.g. KeyboardCore) whose frames count as app frames although Firebase \
            labels them third-party. Repeatable; --scan adds the repo's framework targets automatically.
            """
    )
    var appLibrary: [String] = []

    var reportFormat: OutputFormat { .text }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        let request = try InitRequest.validated(
            scan: scan, appId: appId, profile: profile, bundleId: bundleId, appLibraries: appLibrary)
        let result = try await container.profileSetupService.setup(request)
        let report = try container.resultEmitter.emit(result, using: InitPresenter(), format: .text)
        // A blocked setup still prints its report; the exit code carries the failure.
        if result.isBlocked { throw ExitCode(1) }
        return report
    }
}
