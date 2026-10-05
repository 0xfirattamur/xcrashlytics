import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write .xcrashlytics.json in the current directory and verify the Firebase setup.",
        discussion: """
        Examples:
          xcrashlytics init --scan
          xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --bundle-id com.example.app

        --scan finds every GoogleService-Info.plist and google-services.json
        under the current directory (skipping build outputs and vendored
        copies) and writes one profile per app, bundle id included.
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
        help: "App bundle id — scopes Xcode Organizer crash scanning to ~/Library/Developer/Xcode/Products/<bundle-id>."
    )
    var bundleId: String?

    func validate() throws {
        if scan {
            guard appId == nil, profile == nil, bundleId == nil else {
                throw ValidationError("--scan discovers app ids, profiles, and bundle ids; drop --app-id/--profile/--bundle-id.")
            }
        } else if appId == nil || profile == nil {
            throw ValidationError("pass --app-id and --profile, or --scan to discover them.")
        }
    }

    func run() async throws {
        try await reportingFailures(jsonOutput: false) {
            try await runWithContext(CommandContext.live())
        }
    }

    private enum Check {
        case ok
        case warn(String)
        case fail(String, hint: [String] = [])

        /// Only failures block writing the config.
        var blocks: Bool {
            if case .fail = self { return true }
            return false
        }

        var passed: Bool {
            if case .ok = self { return true }
            return false
        }

        var line: String? {
            switch self {
            case .ok:
                return nil
            case .warn(let message):
                return "[WARN] \(message)"
            case .fail(let message, let hint):
                return (["[FAIL] \(message)"] + hint.map { "          \($0)" }).joined(
                    separator: "\n")
            }
        }
    }

    @discardableResult
    func runWithContext(_ ctx: CommandContext) async throws -> String {
        let discovered = scan
            ? try FirebaseAppDiscovery(fs: ctx.fileSystem).discover(from: FileManager.default.currentDirectoryPath)
            : []
        let checks = try await verifySetup(ctx: ctx, discovered: discovered)
        let blocked = checks.contains { $0.blocks }
        let warned = checks.contains { if case .warn = $0 { return true } else { return false } }

        var lines = discovered.isEmpty ? [] : ["Found \(discovered.count) Firebase app(s):"] + discovered.map {
            "  \($0.profileName)   \($0.platform)   \($0.appId)   \($0.bundleId ?? "-")   (\($0.sourcePath))"
        }
        lines += checks.compactMap(\.line)
        if blocked {
            lines.append("Some checks failed. Fix the above, then re-run `xcrashlytics init`.")
        } else {
            let active = try writeConfig(ctx: ctx, discovered: discovered)
            lines.append(
                warned
                    ? "Setup OK — warnings above are advisory."
                    : "All checks passed.")
            lines.append(
                ".xcrashlytics.json written. It holds app ids only, no secrets"
                    + " — commit it so the team shares the setup.")
            lines.append(active.map { "Active profile: \($0)." }
                ?? "No active profile yet — pick one: xcrashlytics use <profile>")
        }

        let output = lines.joined(separator: "\n") + "\n"
        ctx.console.output(output)
        if blocked { throw ExitCode(1) }
        return output
    }

    private func verifySetup(ctx: CommandContext, discovered: [DiscoveredFirebaseApp]) async throws -> [Check] {
        let cli = checkFirebaseCLI(ctx: ctx)
        let login = try await checkFirebaseLogin(ctx: ctx, isFirebaseCLIInstalled: cli.passed)
        guard scan else {
            return [cli, login, checkAppId(appId ?? ""), checkBundleId(bundleId, ctx: ctx)]
        }
        guard !discovered.isEmpty else {
            return [cli, login, .fail(
                "no GoogleService-Info.plist or google-services.json found under \(FileManager.default.currentDirectoryPath).",
                hint: ["Run from the repo root, or: xcrashlytics init --app-id <APP_ID> --profile <name>"])]
        }
        let missingBundle = discovered.filter { $0.bundleId == nil }.map {
            Check.warn("\($0.profileName): no bundle id in \($0.sourcePath) — Xcode crash commands need one.")
        }
        return [cli, login] + missingBundle
    }

    /// Writes the profile(s) and returns the active profile name, if any.
    /// A scan never guesses among several apps: it keeps a still-valid active
    /// profile, activates a lone discovery, and otherwise leaves it unset.
    private func writeConfig(ctx: CommandContext, discovered: [DiscoveredFirebaseApp]) throws -> String? {
        let store = ConfigFile(fileSystem: ctx.fileSystem)
        var config = (try? store.load()) ?? Config()
        if scan {
            for app in discovered {
                config.profiles[app.profileName] = AppProfile(
                    appId: app.appId, bundleId: app.bundleId, sourcePath: app.sourcePath)
            }
            if config.activeProfile.map({ config.profiles[$0] == nil }) ?? true {
                config.activeProfile = discovered.count == 1 ? discovered[0].profileName : nil
            }
        } else if let appId, let profile {
            let name = profile.lowercased()
            config.profiles[name] = AppProfile(appId: appId, bundleId: bundleId)
            config.activeProfile = name
        }
        try store.save(config)
        return config.activeProfile
    }

    private func checkFirebaseCLI(ctx: CommandContext) -> Check {
        let installed =
            (try? ctx.processRunner.run(
                executable: "/usr/bin/env",
                arguments: ["which", "firebase"],
                stdin: nil
            ))?.exitCode == 0
        guard installed else {
            return .fail(
                "firebase CLI is not installed. Install it, then run `firebase login`:",
                hint: [
                    "npm install -g firebase-tools   # or: brew install firebase-cli",
                    "firebase login",
                ])
        }
        return .ok
    }

    private func checkFirebaseLogin(ctx: CommandContext, isFirebaseCLIInstalled: Bool) async throws
        -> Check {
        let provider = FirebaseToolsTokenProvider(fs: ctx.fileSystem, httpTransport: ctx.httpTransport)
        guard provider.isFirebaseLoggedIn() else {
            return isFirebaseCLIInstalled
                ? .fail("firebase login not completed. Run: firebase login") : .ok
        }
        do {
            _ = try await provider.token()
            return .ok
        } catch let e as AccessTokenError {
            switch e {
            case .refreshTokenInvalid:
                return .fail("firebase refresh token is invalid. Run: firebase login --reauth")
            case .tokenExchangeFailed(let detail):
                return .warn("firebase token exchange failed: \(detail)")
            case .firebaseLoginRequired:
                return .fail("firebase login required. Run: firebase login")
            }
        }
    }

    private func checkAppId(_ appId: String) -> Check {
        guard CrashlyticsClient.projectNumber(fromAppId: appId) != nil else {
            return .fail(
                "appId=\(appId) has wrong format. Expected '1:<number>:<platform>:<hash>'.")
        }
        return .ok
    }

    /// Advisory only — a missing bundle id never blocks the config write, but
    /// Xcode crash commands will refuse to run until one is set.
    private func checkBundleId(_ bundleId: String?, ctx: CommandContext) -> Check {
        guard let bundleId else {
            return .warn("no bundle id — Xcode crash commands need one. Re-run with --bundle-id <BUNDLE_ID>.")
        }
        let crashes = XcodeCrashLoader.standardDirectories(bundleId: bundleId).flatMap {
            (try? ctx.fileSystem.enumerate(at: $0, matchingExtensions: ["crash"])) ?? []
        }
        guard !crashes.isEmpty else {
            return .warn("no Organizer crashes for \(bundleId) yet — open Xcode Organizer once to download.")
        }
        return .ok
    }
}
