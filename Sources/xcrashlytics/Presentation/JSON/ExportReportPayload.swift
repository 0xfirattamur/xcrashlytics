import Foundation

struct ExportReportPayload: Encodable, Sendable {
    var id: String
    var title: String
    var source: String
    var issueId: String?
    var consoleURL: String?
    var crash: Crash
    var impact: ImpactPayload?
    var firstSeenVersion: String?
    var lastSeenVersion: String?
    var dailyEvents: [DailyEventCountPayload]?
    var sample: ActivityPayload?
    var breakdown: Breakdown?
    var versionRange: VersionRangePayload?
    var occurrence: Occurrence
    var frames: [StackFramePayload]
    var exportedAt: Date
    var toolVersion: String

    struct Breakdown: Encodable, Sendable {
        var window: ReportWindowSummary
        var versions: [BreakdownRowPayload]?
        var operatingSystems: [BreakdownRowPayload]?
        var devices: [BreakdownRowPayload]?
    }

    struct Crash: Encodable, Sendable {
        var type: String
        var signal: String?
        var subtype: String?
        var crashMessage: String?
        var module: String?
        var file: String?
        var symbol: String?
        var topSourceFrame: StackFramePayload?
    }

    struct Occurrence: Encodable, Sendable {
        var id: String?
        var time: Date?
        var appVersion: String?
        var appBuild: String?
        var osVersion: String?
        var deviceModel: String?
        var bundleId: String?
        var processState: String?
    }

    init(_ report: ExportReport) {
        id = report.id
        title = report.title
        source = report.source.rawValue
        issueId = report.issueId
        consoleURL = report.consoleURL
        crash = Crash(
            type: report.crash.type, signal: report.crash.signal, subtype: report.crash.subtype,
            crashMessage: report.crash.crashMessage, module: report.crash.module, file: report.crash.file,
            symbol: report.crash.symbol, topSourceFrame: report.crash.topSourceFrame.map(StackFramePayload.init))
        impact = report.impact
        firstSeenVersion = report.firstSeenVersion
        lastSeenVersion = report.lastSeenVersion
        dailyEvents = report.dailyEvents?.map(DailyEventCountPayload.init)
        sample = report.sample
        breakdown = report.breakdown.map {
            Breakdown(
                window: $0.window, versions: $0.versions?.map(BreakdownRowPayload.init),
                operatingSystems: $0.operatingSystems?.map(BreakdownRowPayload.init),
                devices: $0.devices?.map(BreakdownRowPayload.init))
        }
        versionRange = report.versionRange.map(VersionRangePayload.init)
        occurrence = Occurrence(
            id: report.occurrence.id, time: report.occurrence.time, appVersion: report.occurrence.appVersion,
            appBuild: report.occurrence.appBuild, osVersion: report.occurrence.osVersion,
            deviceModel: report.occurrence.deviceModel, bundleId: report.occurrence.bundleId,
            processState: report.occurrence.processState)
        frames = report.frames.map(StackFramePayload.init)
        exportedAt = report.exportedAt
        toolVersion = report.toolVersion
    }
}
