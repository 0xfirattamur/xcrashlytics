import Foundation

struct EventsTextRenderer: Sendable {
    private static let columnSeparator = "   "
    private static let bytesPerMiB = 1_048_576.0

    // MARK: - Public rendering

    /// One summary row per event, followed by the crash message when there is one.
    func text(_ issueEvents: [IssueEvents], filter: FrameFilter, selector: FrameSelector) -> String {
        let rows = eventRows(of: issueEvents) { event, id in
            let frame = selector.topFrameDescription(for: event, filter: filter) ?? "no frames"
            let columns = summaryColumns(of: event, id: id) + [memorySummary(for: event), frame]
            let row = columns.compactMap { $0 }.joined(separator: Self.columnSeparator)
            return ([row] + crashMessageLines(for: event)).joined(separator: "\n")
        }
        return joined(rows, issueEvents)
    }

    /// A header per event followed by its full filtered stack, with blamed frames starred.
    func framesOnlyText(_ issueEvents: [IssueEvents], filter: FrameFilter, selector: FrameSelector) -> String {
        let rows = eventRows(of: issueEvents) { event, id in
            let headerColumns = summaryColumns(of: event, id: id).compactMap { $0 }
            let header = headerColumns.joined(separator: Self.columnSeparator)
            let frames = selector.filteredFrames(from: event, filter: filter)
            let body = frames.isEmpty
                ? [emptyFramesNote(event: event, filter: filter, selector: selector)]
                : frameLines(frames, of: event, selector: selector)
            return ([header] + crashMessageLines(for: event) + body).joined(separator: "\n")
        }
        return joined(rows, issueEvents)
    }

    // MARK: - Layout

    private func eventRows(of issueEvents: [IssueEvents], row: (CrashlyticsEvent, String) -> String) -> [String] {
        issueEvents.flatMap { group in
            group.events.map { event in
                let id = CrashlyticsIdFormatter.canonicalEventId(event, issueId: group.issueId)
                return row(event, id)
            }
        }
    }

    private func joined(_ rows: [String], _ issueEvents: [IssueEvents]) -> String {
        guard !rows.isEmpty else {
            let issueIds = issueEvents.map(\.issueId).joined(separator: ", ")
            return "No Firebase events found for \(issueIds).\n"
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func frameLines(
        _ frames: [CrashlyticsFrame], of event: CrashlyticsEvent, selector: FrameSelector
    ) -> [String] {
        frames.enumerated().map { position, frame in
            let marker = selector.isBlamed(frame, in: event) ? "*" : " "
            let location = selector.location(for: frame)
            let symbol = frame.symbol ?? "?"
            let symbolicated = frame.symbolicated.map { " [\($0)]" } ?? ""
            return "  \(marker) \(position) \(location) \(symbol)\(symbolicated)"
        }
    }

    private func emptyFramesNote(event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector) -> String {
        let note = FrameFilterNote(event: event, filter: filter, selector: selector)
        return "  " + note.textLine
    }

    // MARK: - Event fragments

    private func summaryColumns(of event: CrashlyticsEvent, id: String) -> [String?] {
        [id, event.eventTime ?? "unknown time", appVersion(for: event), runtimeSummary(for: event)]
    }

    private func crashMessageLines(for event: CrashlyticsEvent) -> [String] {
        guard let message = EventDetailView(event).crashMessage else { return [] }
        let continuationIndent = "\n" + String(repeating: " ", count: 11)
        return ["    crash: " + message.replacingOccurrences(of: "\n", with: continuationIndent)]
    }

    private func appVersion(for event: CrashlyticsEvent) -> String? {
        switch (event.displayVersion, event.buildVersion) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "build \(build)"
        case (nil, nil):
            return nil
        }
    }

    private func runtimeSummary(for event: CrashlyticsEvent) -> String? {
        let os = event.osVersion.map { PlatformLabelFormatter.os($0, platform: event.platform) }
        let parts = [event.deviceModel, os].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func memorySummary(for event: CrashlyticsEvent) -> String? {
        event.memoryFree.map { String(format: "%.2f MiB free RAM", Double($0) / Self.bytesPerMiB) }
    }
}
