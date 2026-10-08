import Foundation

// Privacy: never carries user ids.
struct ExportReport: Sendable {
    var id: String
    var title: String
    var source: CrashSource
    var issueId: String?
    var consoleURL: String?
    var crash: Crash
    var impact: ImpactPayload?
    /// Version of the issue's first event; with `lastSeenVersion` chronological, not a range.
    var firstSeenVersion: String?
    /// Version of the issue's most recent event; can be lower than `firstSeenVersion`.
    var lastSeenVersion: String?
    var dailyEvents: [DailyEventCount]?
    /// Spread across the newest sampled events of the export window, not the issue's full history.
    var sample: ActivityPayload?
    /// Exact spreads from the Crashlytics reports over the export window: the top rows
    /// by events per dimension. A dimension whose report failed is absent (see `sample`).
    var breakdown: Breakdown?
    var versionRange: VersionRange?
    var occurrence: Occurrence
    var frames: [StackFrame]
    var exportedAt: Date
    var toolVersion: String

    struct Breakdown: Sendable {
        static let topCount = 5

        var window: ReportWindowSummary
        var versions: [BreakdownRow]?
        var operatingSystems: [BreakdownRow]?
        var devices: [BreakdownRow]?

        init(_ spreads: CrashSpreads) {
            window = ReportWindowSummary(spreads.window)
            versions = spreads.versions.map { Array($0.prefix(Self.topCount)) }
            operatingSystems = spreads.operatingSystems.map { Array($0.prefix(Self.topCount)) }
            devices = spreads.devices.map { Array($0.prefix(Self.topCount)) }
        }
    }

    struct Crash: Sendable {
        /// Firebase: FATAL / NON_FATAL / ANR (the issue's error type). Xcode: the Mach exception type.
        var type: String
        var signal: String?
        var subtype: String?
        var crashMessage: String?
        var module: String?
        var file: String?
        var symbol: String?
        var topSourceFrame: StackFrame?
    }

    struct Occurrence: Sendable {
        var id: String?
        var time: Date?
        var appVersion: String?
        var appBuild: String?
        var osVersion: String?
        var deviceModel: String?
        var bundleId: String?
        var processState: String?
    }

    init(_ result: CrashExportResult, toolVersion: String) {
        let crashDetail = result.detail
        let event = crashDetail.event
        let issue = crashDetail.issue
        let firebaseEvent = crashDetail.firebaseEvent ?? crashDetail.latestEvent

        id = event.id
        title = issue?.title ?? event.exception.description ?? event.exception.exceptionType
        source = event.source
        issueId = issue.flatMap { $0.id == event.id ? nil : $0.id }
        consoleURL = issue?.consoleURL
        crash = Self.makeCrash(crashDetail, firebaseEvent: firebaseEvent)
        impact = crashDetail.impact.map(ImpactPayload.init)
        firstSeenVersion = issue?.firstSeenVersion
        lastSeenVersion = issue?.lastSeenVersion
        dailyEvents = crashDetail.dailyEvents
        sample = crashDetail.activity.map(ActivityPayload.init)
        breakdown = result.spreads.map(Breakdown.init)
        versionRange = result.versionRange
        occurrence = Self.makeOccurrence(crashDetail, firebaseEvent: firebaseEvent)
        frames = event.frames
        exportedAt = result.exportedAt
        self.toolVersion = toolVersion
    }

    // MARK: - Construction helpers

    private static func makeCrash(_ crashDetail: CrashDetail, firebaseEvent: CrashlyticsEvent?) -> Crash {
        let event = crashDetail.event
        let issue = crashDetail.issue
        let signature = issue.flatMap(IssueDisplaySignature.init)
        let topSourceFrame = firstAppSourceFrame(of: event)
        // Unlocated stacks (most local reports) still name a culprit: the first symbolicated non-runtime frame.
        let culpritFrame = topSourceFrame ?? FrameNormalizer.meaningful(event.frames).first { $0.isSymbolicated }
        return Crash(
            type: issue?.errorType ?? event.exception.exceptionType,
            signal: event.exception.signal,
            subtype: event.exception.subtype,
            crashMessage: firebaseEvent.flatMap { EventDetailView($0).crashMessage },
            module: signature?.module ?? culpritFrame?.binaryName,
            file: signature?.file ?? culpritFrame?.file,
            symbol: signature?.symbol ?? culpritFrame?.symbol,
            topSourceFrame: topSourceFrame
        )
    }

    /// Non-fatal titles and stacks start inside the SDK call that recorded the error;
    /// the culprit is the app code that called it.
    private static func firstAppSourceFrame(of event: CrashEvent) -> StackFrame? {
        let sdkDetector = CrashlyticsSDKDetector()
        return event.frames.first { frame in
            guard frame.file != nil else { return false }
            let isSDKFrame = sdkDetector.isCrashlyticsSDKCode(
                symbol: frame.symbol, file: frame.file, library: frame.binaryName)
            return !isSDKFrame
        }
    }

    private static func makeOccurrence(
        _ crashDetail: CrashDetail, firebaseEvent: CrashlyticsEvent?
    ) -> Occurrence {
        let event = crashDetail.event
        let canonicalEventId = firebaseEvent.flatMap { firebaseEvent in
            crashDetail.issue.map { issue in
                CrashlyticsIdFormatter.canonicalEventId(firebaseEvent, issueId: issue.providerId)
            }
        }
        return Occurrence(
            id: canonicalEventId,
            time: event.timestamp ?? firebaseEvent?.eventTime.flatMap(EventTimestampParser.parse),
            appVersion: firebaseEvent?.displayVersion ?? event.bundleVersion,
            appBuild: firebaseEvent?.buildVersion,
            osVersion: event.osVersion ?? firebaseEvent?.osVersion,
            deviceModel: event.deviceModel ?? firebaseEvent?.deviceModel,
            bundleId: event.bundleId ?? firebaseEvent?.bundleOrPackage,
            processState: firebaseEvent?.processState
        )
    }
}
