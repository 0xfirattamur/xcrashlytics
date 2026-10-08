import Foundation

struct MarkdownRenderer: Sendable {
    private typealias TableRow = (field: String, value: String)

    private struct SpreadLine {
        var title: String
        var description: String
    }

    private static let secondsPerDay = 86_400.0

    private let text = CrashDetailTextRenderer()
    private let minuteFormatter = UTCDateFormatter.make(UTCDateFormatter.minuteFormat)
    private let dayFormatter = UTCDateFormatter.make(UTCDateFormatter.dayFormat)

    // MARK: - Document

    func render(_ report: ExportReport) -> String {
        var document: [String] = ["# \(singleLine(report.title))", ""]
        document += summary(report)
        document += section("Details", table(details(report)))
        document += section("Where it happens", whereItHappens(report))
        document += section(occurrenceTitle(report), table(occurrenceRows(report.occurrence)))
        document += section("Stack trace", stackLines(report))
        document += footer(report)
        return document.joined(separator: "\n") + "\n"
    }

    private func occurrenceTitle(_ report: ExportReport) -> String {
        let isLatestFirebaseEvent = report.source == .firebase && report.issueId == nil
        return isLatestFirebaseEvent ? "Latest occurrence" : "Occurrence"
    }

    private func footer(_ report: ExportReport) -> [String] {
        let exportedAt = minuteFormatter.string(from: report.exportedAt)
        return ["", "---", "_Exported with xcrashlytics \(report.toolVersion) on \(exportedAt)._"]
    }

    // MARK: - Summary

    private func summary(_ report: ExportReport) -> [String] {
        var lines = [whatLine(report.crash)]
        if let impact = report.impact {
            lines.append(impactLine(impact))
        }
        if let days = report.dailyEvents, !days.isEmpty {
            let trend = days.map { "\($0.day): \($0.eventsCount)" }.joined(separator: " · ")
            lines.append("**Trend (events per day, UTC):** " + trend)
        }
        if let seen = IssueSeenVersions.description(first: report.firstSeenVersion, last: report.lastSeenVersion) {
            lines.append("**Versions:** \(seen) (versions of the first and the latest event, not a range)")
        }
        if let range = report.versionRange {
            let note = "lowest and highest app version with events in the window"
            lines.append("**Version range:** \(range.min) … \(range.max) (\(note))")
        }
        return lines.map { $0 + "  " }
    }

    private func whatLine(_ crash: ExportReport.Crash) -> String {
        var what = "**What:** `\(crash.type)`" + typeSignalSuffix(crash)
        if let symbol = crash.symbol {
            what += " in `\(singleLine(symbol))`"
        }
        if let file = crash.file {
            let sameFileAsTopFrame = crash.topSourceFrame?.file == file
            let line = sameFileAsTopFrame ? crash.topSourceFrame?.line : nil
            what += " — `\(file)\(lineSuffix(line))`"
        }
        if let message = crash.crashMessage {
            what += " — \"\(singleLine(message))\""
        }
        return what
    }

    private func impactLine(_ impact: ImpactPayload) -> String {
        let usersShare = impact.impactedUsersPercentage.map { percentage in
            String(format: " (%.2f%% of %d)", percentage, impact.appUsersCount ?? 0)
        }
        return "**Impact (\(windowDescription(impact))):** \(impact.eventsCount) events · "
            + "\(impact.impactedUsersCount) users\(usersShare ?? "")"
    }

    private func windowDescription(_ impact: ImpactPayload) -> String {
        let days = Int((impact.until.timeIntervalSince(impact.since) / Self.secondsPerDay).rounded())
        let range = "\(dayFormatter.string(from: impact.since)) → \(dayFormatter.string(from: impact.until))"
        guard days >= 1 else { return range }
        return "last \(days) day\(days == 1 ? "" : "s"), \(range)"
    }

    // MARK: - Details

    private func details(_ report: ExportReport) -> [TableRow] {
        let crash = report.crash
        var rows: [TableRow] = [("ID", "`\(report.id)`")]
        if let issueId = report.issueId {
            rows.append(("Issue", "`\(issueId)`"))
        }
        if let url = report.consoleURL {
            rows.append(("Firebase console", "[Open issue](\(url))"))
        }
        rows.append(("Source", report.source.rawValue))
        rows.append(("Type", "`\(crash.type)`" + typeSignalSuffix(crash)))
        if let subtype = crash.subtype {
            rows.append(("Subtype", subtype))
        }
        if let message = crash.crashMessage {
            rows.append(("Crash message", message))
        }
        if let module = crash.module {
            rows.append(("Module", module))
        }
        if let frame = crash.topSourceFrame, let file = frame.file {
            rows.append(("Top source frame", "`\(file)\(lineSuffix(frame.line))` \(frame.symbol ?? "")"))
        }
        return rows
    }

    private func occurrenceRows(_ occurrence: ExportReport.Occurrence) -> [TableRow] {
        var rows: [TableRow] = []
        if let id = occurrence.id {
            rows.append(("Event", "`\(id)`"))
        }
        if let time = occurrence.time {
            rows.append(("Time", minuteFormatter.string(from: time)))
        }
        if let version = occurrence.appVersion {
            let build = occurrence.appBuild.map { " (\($0))" } ?? ""
            rows.append(("App version", version + build))
        }
        if let os = occurrence.osVersion {
            rows.append(("OS", os))
        }
        if let device = occurrence.deviceModel {
            rows.append(("Device", device))
        }
        if let bundle = occurrence.bundleId {
            rows.append(("Bundle", bundle))
        }
        if let state = occurrence.processState {
            rows.append(("Process state", state))
        }
        return rows
    }

    // MARK: - Where it happens

    private func whereItHappens(_ report: ExportReport) -> [String] {
        guard let breakdown = report.breakdown else {
            return report.sample.map(sampleLines) ?? []
        }
        let exactDimensions = exactDimensions(of: breakdown)
        var lines = breakdownIntroLines(breakdown)
        for dimension in exactDimensions {
            guard let rows = dimension.rows else { continue }
            let described = rows.isEmpty
                ? "no events in the window"
                : rows.map(breakdownDescription).joined(separator: "; ")
            lines.append("- \(dimension.title): \(described)")
        }
        let missingTitles = exactDimensions.filter { $0.rows == nil }.map(\.title)
        if let sample = report.sample {
            lines += sampledInsteadLines(sample, missingTitles: missingTitles)
        }
        return lines
    }

    private typealias ExactDimension = (title: String, rows: [BreakdownRow]?)

    private func exactDimensions(of breakdown: ExportReport.Breakdown) -> [ExactDimension] {
        [
            ("App versions", breakdown.versions),
            ("OS", breakdown.operatingSystems),
            ("Devices", breakdown.devices)
        ]
    }

    private func breakdownIntroLines(_ breakdown: ExportReport.Breakdown) -> [String] {
        let since = dayFormatter.string(from: breakdown.window.since)
        let until = dayFormatter.string(from: breakdown.window.until)
        let intro = "Exact counts from the Crashlytics reports over the export window (\(since) → \(until)), "
            + "top \(ExportReport.Breakdown.topCount) by events."
        return [intro, ""]
    }

    /// Fills the dimensions whose exact report failed with the (approximate) sampled spread.
    private func sampledInsteadLines(_ sample: ActivityPayload, missingTitles: [String]) -> [String] {
        let spreads = spreadLines(of: sample).filter { missingTitles.contains($0.title) }
        guard !spreads.isEmpty else { return [] }
        let heading = "Sampled instead (newest \(sample.sampledEvents) events, not exact):"
        return ["", heading] + spreads.map(bullet)
    }

    private func breakdownDescription(_ row: BreakdownRow) -> String {
        var description = "\(breakdownName(row)) \(row.eventsCount) events"
        if let share = row.eventsShare {
            description += isTinyShare(share) ? " (<0.1%)" : String(format: " (%.1f%%)", share)
        }
        description += " · \(row.impactedUsersCount) users"
        if let percentage = row.impactedUsersPercentage, let versionUsers = row.versionUsersCount {
            description += String(format: " (%.2f%% of %d)", percentage, versionUsers)
        }
        return description
    }

    private func breakdownName(_ row: BreakdownRow) -> String {
        guard let marketingName = row.marketingName else { return row.name }
        return "\(marketingName) (\(row.model ?? row.name))"
    }

    private func isTinyShare(_ share: Double) -> Bool {
        share > 0 && share < 0.1
    }

    private func sampleLines(_ sample: ActivityPayload) -> [String] {
        var lines = [sampleSummary(sample) + "."]
        let spreads = spreadLines(of: sample)
        if !spreads.isEmpty {
            lines.append("")
            lines += spreads.map(bullet)
        }
        return lines
    }

    private func sampleSummary(_ sample: ActivityPayload) -> String {
        var summary = "Newest \(sample.sampledEvents) sampled events"
        if let first = sample.firstEventAt, let last = sample.lastEventAt {
            let firstDay = EventTimestampParser.dayString(from: first) ?? first
            let lastDay = EventTimestampParser.dayString(from: last) ?? last
            summary += ", \(firstDay) → \(lastDay)"
        }
        if let users = sample.distinctUsers {
            summary += ", \(users) users"
        }
        return summary
    }

    /// Non-empty sampled spreads, in display order.
    private func spreadLines(of sample: ActivityPayload) -> [SpreadLine] {
        let spreads: [(title: String, entries: [(name: String, count: Int)])] = [
            ("App versions", sample.versionSpread.map { ($0.name, $0.count) }),
            ("OS", sample.osSpread.map { ($0.name, $0.count) }),
            ("Devices", sample.deviceSpread.map { ($0.name, $0.count) })
        ]
        return spreads
            .filter { !$0.entries.isEmpty }
            .map { SpreadLine(title: $0.title, description: text.spreadDescription($0.entries)) }
    }

    private func bullet(_ spread: SpreadLine) -> String {
        "- \(spread.title): \(spread.description)"
    }

    // MARK: - Stack trace

    private func stackLines(_ report: ExportReport) -> [String] {
        guard !report.frames.isEmpty else { return ["_No frames available._"] }
        return ["```text"] + report.frames.map(text.renderFrame) + ["```"]
    }

    // MARK: - Markdown helpers

    private func section(_ title: String, _ body: [String]) -> [String] {
        guard !body.isEmpty else { return [] }
        return ["", "## \(title)", ""] + body
    }

    private func table(_ rows: [TableRow]) -> [String] {
        guard !rows.isEmpty else { return [] }
        let body = rows.map { "| \($0.field) | \(cell($0.value)) |" }
        return ["| Field | Value |", "| --- | --- |"] + body
    }

    /// Table cells end at a newline or an unescaped pipe.
    private func cell(_ value: String) -> String {
        singleLine(value).replacingOccurrences(of: "|", with: "\\|")
    }

    private func singleLine(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func typeSignalSuffix(_ crash: ExportReport.Crash) -> String {
        crash.signal.map { " (\($0))" } ?? ""
    }

    private func lineSuffix(_ line: Int?) -> String {
        line.map { ":\($0)" } ?? ""
    }
}
