import Foundation

struct CrashDetailTextRenderer: Sendable {
    private static let maxListedEntries = 5
    private static let fieldLabelWidth = 11
    private static let indexColumnWidth = 3
    private static let binaryColumnWidth = 32

    private let dateFormatter = UTCDateFormatter.make(UTCDateFormatter.minuteFormat)

    // MARK: - Rendering

    func render(_ crashDetail: CrashDetail, includeBreadcrumbs: Bool) -> String {
        let event = crashDetail.event
        let sourceEvent = crashDetail.firebaseEvent ?? crashDetail.latestEvent

        var lines = headerLines(crashDetail)
        lines += crashMessageLines(sourceEvent, includeBreadcrumbs: includeBreadcrumbs)
        lines += issueLines(crashDetail.issue, versionRange: crashDetail.versionRange)
        if let activity = crashDetail.activity {
            lines += activityLines(activity)
        }
        lines += attributionLines(of: crashDetail)
        lines.append("")
        lines.append("Thread \(event.crashedThreadIndex) (crashed):")
        lines += event.frames.map(renderFrame)
        lines += frameFilterNoteLines(crashDetail, sourceEvent: sourceEvent)
        return lines.joined(separator: "\n") + "\n"
    }

    func renderFrame(_ frame: StackFrame) -> String {
        let index = padded(String(frame.index), toWidth: Self.indexColumnWidth, alignRight: true)
        // `%-32@` does not pad in String(format:); pad by hand, never truncating long names.
        let binary = padded(frame.binaryName, toWidth: Self.binaryColumnWidth)
        let address = frame.address.map { String(format: "0x%016llx", $0) + "  " } ?? ""
        let symbol = frame.symbol ?? "<no symbol>"
        let symbolicated = frame.symbolicated.map { " [\($0)]" } ?? ""
        return "\(index)  \(binary)  \(address)\(symbol)\(location(of: frame))\(symbolicated)"
    }

    func spreadDescription(_ spread: [(name: String, count: Int)]) -> String {
        let entries = spread.map { "\($0.name) ×\($0.count)" }
        return listedEntries(entries)
    }

    // MARK: - Header

    private func headerLines(_ crashDetail: CrashDetail) -> [String] {
        let event = crashDetail.event
        var lines = [
            field("ID", event.id),
            field("Source", event.source.rawValue)
        ]
        if let bundle = event.bundleId {
            lines.append(field("Bundle", bundle))
        }
        if let version = event.bundleVersion {
            let build = crashDetail.firebaseEvent?.buildVersion.map { " (\($0))" } ?? ""
            lines.append(field("Version", version + build))
        }
        if let os = event.osVersion {
            lines.append(field("OS", os))
        }
        if let model = event.deviceModel {
            lines.append(field("Device", model))
        }
        if let timestamp = event.timestamp {
            lines.append(field("Time", dateFormatter.string(from: timestamp)))
        }
        let signal = event.exception.signal.map { " (\($0))" } ?? ""
        lines.append(field("Exception", event.exception.exceptionType + signal))
        if let subtype = event.exception.subtype {
            lines.append(field("Subtype", subtype))
        }
        return lines
    }

    private func crashMessageLines(_ sourceEvent: CrashlyticsEvent?, includeBreadcrumbs: Bool) -> [String] {
        guard let sourceEvent else { return [] }
        let view = EventDetailView(sourceEvent, includeBreadcrumbs: includeBreadcrumbs)
        guard let message = view.crashMessage else { return [] }
        return [field("Crash", message)]
    }

    private func frameFilterNoteLines(_ crashDetail: CrashDetail, sourceEvent: CrashlyticsEvent?) -> [String] {
        guard let sourceEvent else { return [] }
        let note = FrameFilterNote.ifEmpty(
            sourceEvent,
            filter: crashDetail.frameFilter,
            selector: crashDetail.frameSelector,
            shownFrameCount: crashDetail.event.frames.count)
        return note.map { ["  " + $0.textLine] } ?? []
    }

    // MARK: - Issue and activity

    private func issueLines(_ issue: CrashIssue?, versionRange: VersionRange?) -> [String] {
        var lines: [String] = []
        if let issue, issue.eventsCount != nil || issue.impactedUsersCount != nil {
            let events = issue.eventsCount.map(String.init) ?? "?"
            let users = issue.impactedUsersCount.map(String.init) ?? "?"
            lines.append(field("Impact", "\(events) events / \(users) users"))
        }
        let seen = IssueSeenVersions.description(first: issue?.firstSeenVersion, last: issue?.lastSeenVersion)
        if let seen {
            lines.append(field("Versions", seen))
        }
        if let versionRange {
            let range = "\(versionRange.min) … \(versionRange.max) (lowest/highest version with events, 90d)"
            lines.append(field("Range", range))
        }
        return lines
    }

    private func activityLines(_ activity: IssueActivitySummary) -> [String] {
        var lines = [field("Sampled", sampledDescription(activity))]
        if !activity.osSpread.isEmpty {
            lines.append(field("OS", spreadDescription(activity.osSpread.map { ($0.name, $0.count) })))
        }
        if !activity.deviceSpread.isEmpty {
            lines.append(field("Devices", spreadDescription(activity.deviceSpread.map { ($0.name, $0.count) })))
        }
        return lines
    }

    private func sampledDescription(_ activity: IssueActivitySummary) -> String {
        var description = "newest \(activity.sampledEvents) events"
        if let first = activity.firstEventAt, let last = activity.lastEventAt {
            let firstDay = EventTimestampParser.dayString(from: first) ?? first
            let lastDay = EventTimestampParser.dayString(from: last) ?? last
            description += ", \(firstDay) → \(lastDay)"
        }
        if let users = activity.distinctUsers {
            description += ", \(users) users"
        }
        return description
    }

    // MARK: - Library attribution

    private func attributionLines(of crashDetail: CrashDetail) -> [String] {
        let builder = LibraryAttributionBuilder(selector: crashDetail.frameSelector)
        guard let attribution = builder.attribution(for: crashDetail.sampledEvents) else { return [] }
        var lines: [String] = []
        if !attribution.dominantLibraries.isEmpty {
            lines.append("Libraries: \(libraryDescription(attribution.dominantLibraries))")
        }
        if !attribution.blameLibraries.isEmpty {
            lines.append("Blamed in: \(libraryDescription(attribution.blameLibraries))")
        }
        return lines
    }

    private func libraryDescription(_ libraries: [LibraryAttribution.Entry]) -> String {
        let entries = libraries.map { library in
            let percent = Int((library.share * 100).rounded())
            return "\(library.library) ×\(library.events) (\(percent)%)"
        }
        return listedEntries(entries)
    }

    // MARK: - Formatting helpers

    /// Shows the first few entries and summarizes the remainder as "+N more".
    private func listedEntries(_ entries: [String]) -> String {
        let shown = entries.prefix(Self.maxListedEntries).joined(separator: ", ")
        let hiddenCount = entries.count - Self.maxListedEntries
        return hiddenCount > 0 ? "\(shown), +\(hiddenCount) more" : shown
    }

    /// One "Label:    value" line; extra lines of a multi-line value align under the first.
    private func field(_ label: String, _ value: String) -> String {
        let prefix = padded(label + ":", toWidth: Self.fieldLabelWidth)
        let continuationIndent = "\n" + String(repeating: " ", count: Self.fieldLabelWidth)
        return prefix + value.replacingOccurrences(of: "\n", with: continuationIndent)
    }

    private func location(of frame: StackFrame) -> String {
        guard let file = frame.file else { return "" }
        guard let line = frame.line else { return " (\(file))" }
        return " (\(file):\(line))"
    }

    private func padded(_ text: String, toWidth width: Int, alignRight: Bool = false) -> String {
        let padding = String(repeating: " ", count: max(0, width - text.count))
        return alignRight ? padding + text : text + padding
    }
}
