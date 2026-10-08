import ArgumentParser
import Foundation

struct ExportCommand: ContainerCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export one crash as a shareable report: what it is, how much it hurts, where it happens.",
        discussion: """
        Takes the same ids as `show`. Writes Markdown (default) or JSON to stdout,
        or to --output. Firebase issues include their event and user totals over
        --since (default 7d, at most 90d, the Crashlytics limit). User ids are
        never included.

        Examples:
          xcrashlytics export FB-3aedb610eee1a41872d991ca62ce8566 | pbcopy
          xcrashlytics export FB-3aedb610eee1a41872d991ca62ce8566 --since 30d --output crash.md
          xcrashlytics export FB-3aedb610eee1a41872d991ca62ce8566/events/E1 --format json
          xcrashlytics export XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE --app-frames-only
        """
    )

    @Argument(help: "Crash id (XC-<uuid>, FB-<id>, FB-<id>/events/<event>) or a Firebase console issue link.")
    var id: String

    @Option(name: .long, help: "Report format: markdown (default) or json.")
    var format: ExportFormat = .markdown

    @Option(name: .long, help: "Firebase issues: window for event and user totals, e.g. 7d, 30d, 90d, or all (90d).")
    var since: String = "7d"

    @Option(name: .long, help: "Write the report to this file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Firebase only: only include frames that look app-owned.")
    var appFramesOnly: Bool = false

    @Flag(name: .long, help: "Firebase only: drop redacted, deduplicated, and known system/SDK frames.")
    var noSystemFrames: Bool = false

    @Flag(
        name: .long,
        help: """
            Firebase only: only include frames of Firebase's crashed thread \
            (warns NO_CRASHED_THREAD when there is none).
            """)
    var crashingThreadOnly: Bool = false

    @Option(
        name: .customLong("crash-directory"),
        help: "XC- ids: Xcode crash directory to scan instead of the profile's Organizer directories. Repeatable.")
    var crashDirectories: [String] = []

    var reportFormat: OutputFormat { format.outputFormat }

    /// Returns the report, whether it went to stdout or `--output`.
    @discardableResult
    func execute(_ container: AppContainer) async throws -> String {
        let result = try await container.crashExportService.export(makeRequest())
        let presenter = ExportPresenter(toolVersion: XcrashlyticsCommand.configuration.version)
        let rendered = try presenter.render(result, format: format)
        guard let output else {
            return container.resultEmitter.emit(rendered, format: reportFormat)
        }
        try writeReport(rendered, of: result, to: output, presenter: presenter, container: container)
        return rendered.body
    }

    private func makeRequest() -> CrashExportRequest {
        let frameFilter = FrameFilter(
            appFramesOnly: appFramesOnly,
            noSystemFrames: noSystemFrames,
            crashingThreadOnly: crashingThreadOnly)
        return CrashExportRequest(
            id: id, since: since, frameFilter: frameFilter, crashDirectories: crashDirectories)
    }

    private func writeReport(
        _ rendered: RenderedOutput,
        of result: CrashExportResult,
        to output: String,
        presenter: ExportPresenter,
        container: AppContainer
    ) throws {
        // Warnings first: a failed write must not swallow them.
        container.resultEmitter.report(rendered.warnings, format: reportFormat)
        let path = try container.crashExportService.write(rendered.body, to: output)
        let confirmation = RenderedOutput(body: presenter.confirmation(for: result, writtenTo: path))
        container.resultEmitter.emit(confirmation, format: reportFormat)
    }
}
