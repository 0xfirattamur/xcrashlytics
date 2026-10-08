import ArgumentParser
import Foundation

struct ShowCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a single crash by id (XC-<uuid>, FB-<id>) or Firebase console link.",
        discussion: """
        Examples:
          xcrashlytics show FB-3aedb610eee1a41872d991ca62ce8566
          xcrashlytics show FB-3aedb610eee1a41872d991ca62ce8566/events/E1 --format json
          xcrashlytics show XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
          xcrashlytics show 'https://console.firebase.google.com/project/p/crashlytics/app/ios:com.example.app/issues/3aed…'

        Console links are matched to the profile whose bundle id equals the
        link's app; quote the link so the shell leaves `?` and `&` alone.
        """
    )

    @Argument(help: "Crash id (XC-<uuid>, FB-<id>, FB-<id>/events/<event>) or a Firebase console issue link.")
    var id: String

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: OutputFormat = .text

    @Flag(name: .long, help: "Firebase only: only emit frames that look app-owned.")
    var appFramesOnly: Bool = false

    @Flag(name: .long, help: "Firebase only: drop redacted, deduplicated, and known system/SDK frames.")
    var noSystemFrames: Bool = false

    @Flag(
        name: .long,
        help: """
            Firebase only: only emit frames of Firebase's crashed thread \
            (warns NO_CRASHED_THREAD when there is none).
            """)
    var crashingThreadOnly: Bool = false

    @Flag(
        name: .long,
        help: """
            Firebase only: include the event's breadcrumbs in JSON (Analytics events before the crash); \
            large, user ids redacted.
            """)
    var breadcrumbs: Bool = false

    @Option(
        name: .long,
        help: """
            Firebase only: a .dSYM bundle, or a directory searched recursively for them, \
            to symbolicate frames of its library (xcrun atos). Repeatable.
            """)
    var dsym: [String] = []

    @Option(
        name: .customLong("crash-directory"),
        help: "XC- ids: Xcode crash directory to scan instead of the profile's Organizer directories. Repeatable.")
    var crashDirectories: [String] = []

    var reportFormat: OutputFormat { format }

    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        try ShowPresenter.requireSupported(format)
        let detail = try await container.crashDetailService.detail(makeRequest())
        let presenter = ShowPresenter(includeBreadcrumbs: breadcrumbs)
        return try container.resultEmitter.emit(detail, using: presenter, format: format)
    }

    private func makeRequest() -> CrashDetailRequest {
        let frameFilter = FrameFilter(
            appFramesOnly: appFramesOnly,
            noSystemFrames: noSystemFrames,
            crashingThreadOnly: crashingThreadOnly)
        return CrashDetailRequest(
            id: id,
            frameFilter: frameFilter,
            crashDirectories: crashDirectories,
            dsymPaths: dsym,
            includesVersionRange: true)
    }
}
