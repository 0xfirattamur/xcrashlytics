import Foundation

/// Renders crashes as plain text for terminal output.
struct PlainTextRenderer: Sendable {
    private let dateFormatter: DateFormatter

    init() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        self.dateFormatter = f
    }

    func renderGroups(_ groups: [CrashGroup]) -> String {
        if groups.isEmpty { return "No crashes found.\n" }
        var lines: [String] = []
        for group in groups {
            let module = group.module.map { " [\($0)]" } ?? ""
            let link = group.isCrossSource ? "  ✓ local repro of prod issue" : ""
            lines.append("▸ \(group.symbol)\(module)\(link)")
            if !group.firebase.isEmpty {
                let metrics = formatMetrics(events: group.totalEvents, users: group.totalUsers)
                lines.append("    firebase: \(group.firebase.count) issue\(group.firebase.count == 1 ? "" : "s")   \(metrics)")
                lines.append("      " + group.firebase.map(\.id).joined(separator: ", "))
            }
            if !group.xcode.isEmpty {
                lines.append("    xcode: \(group.xcode.count) crash\(group.xcode.count == 1 ? "" : "es")")
                lines.append("      " + group.xcode.map(\.event.id).joined(separator: ", "))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatMetrics(events: Int?, users: Int?) -> String {
        if events == nil && users == nil { return "" }
        let e = events.map(String.init) ?? "?"
        let u = users.map(String.init) ?? "?"
        return "\(e) events / \(u) users"
    }

    func renderDetail(
        _ event: CrashEvent,
        issue: CrashIssue? = nil,
        activity: IssueActivitySummary? = nil
    ) -> String {
        var out: [String] = []
        out.append("ID:        \(event.id)")
        out.append("Source:    \(event.source.rawValue)")
        if let bundle = event.bundleId { out.append("Bundle:    \(bundle)") }
        if let version = event.bundleVersion { out.append("Version:   \(version)") }
        if let os = event.osVersion { out.append("OS:        \(os)") }
        if let model = event.deviceModel { out.append("Device:    \(model)") }
        if let ts = event.timestamp {
            out.append("Time:      \(dateFormatter.string(from: ts))")
        }
        out.append("Exception: \(event.exception.exceptionType)\(event.exception.signal.map { " (\($0))" } ?? "")")
        if let subtype = event.exception.subtype {
            out.append("Subtype:   \(subtype)")
        }
        if let issue, issue.eventsCount != nil || issue.impactedUsersCount != nil {
            let events = issue.eventsCount.map(String.init) ?? "?"
            let users = issue.impactedUsersCount.map(String.init) ?? "?"
            out.append("Impact:    \(events) events / \(users) users")
        }
        if let activity {
            out.append(contentsOf: activityLines(activity))
        }
        out.append("")
        out.append("Thread \(event.crashedThreadIndex) (crashed):")
        for f in event.frames {
            out.append(renderFrame(f))
        }
        return out.joined(separator: "\n") + "\n"
    }

    private func activityLines(_ activity: IssueActivitySummary) -> [String] {
        var lines: [String] = []
        var sampled = "Sampled:   newest \(activity.sampledEvents) events"
        if let first = activity.firstEventAt, let last = activity.lastEventAt {
            let firstDay = EventDates.dayString(from: first) ?? first
            let lastDay = EventDates.dayString(from: last) ?? last
            sampled += ", \(firstDay) → \(lastDay)"
        }
        if let users = activity.distinctUsers {
            sampled += ", \(users) users"
        }
        lines.append(sampled)
        if !activity.osSpread.isEmpty {
            lines.append("OS:        \(spreadDescription(activity.osSpread))")
        }
        if !activity.deviceSpread.isEmpty {
            lines.append("Devices:   \(spreadDescription(activity.deviceSpread))")
        }
        return lines
    }

    private func spreadDescription(_ spread: [SpreadCount]) -> String {
        let shown = spread.prefix(5).map { "\($0.name) ×\($0.count)" }.joined(separator: ", ")
        let rest = spread.count - 5
        return rest > 0 ? "\(shown), +\(rest) more" : shown
    }

    private func renderFrame(_ f: Frame) -> String {
        let symbol = f.symbol ?? "<no symbol>"
        let location: String = {
            guard let file = f.file else { return "" }
            if let line = f.line { return " (\(file):\(line))" }
            return " (\(file))"
        }()
        guard let address = f.address else {
            return String(
                format: "%3d  %-32@  %@%@",
                f.index,
                f.binaryName as NSString,
                symbol,
                location
            )
        }
        return String(
            format: "%3d  %-32@  %@  %@%@",
            f.index,
            f.binaryName as NSString,
            String(format: "0x%016llx", address),
            symbol,
            location
        )
    }
}
