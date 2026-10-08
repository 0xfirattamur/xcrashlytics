struct GroupsTextRenderer: Sendable {
    func render(_ groups: [CrashGroup]) -> String {
        guard !groups.isEmpty else { return "No crashes found.\n" }
        let lines = groups.flatMap(groupLines)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Group

    private func groupLines(_ group: CrashGroup) -> [String] {
        var lines = [headline(group)]
        if !group.firebase.isEmpty {
            lines += firebaseLines(group)
        }
        if !group.xcode.isEmpty {
            lines += xcodeLines(group)
        }
        lines.append("")
        return lines
    }

    private func headline(_ group: CrashGroup) -> String {
        let module = group.module.map { " [\($0)]" } ?? ""
        let link = group.isCrossSource ? "  ✓ local repro of prod issue" : ""
        return "▸ \(group.symbol)\(module)\(link)"
    }

    private func firebaseLines(_ group: CrashGroup) -> [String] {
        let count = group.firebase.count
        let metrics = metricsDescription(events: group.totalEvents, users: group.totalUsers)
        return [
            "    firebase: \(count) issue\(count == 1 ? "" : "s")   \(metrics)",
            "      " + group.firebase.map(\.id).joined(separator: ", ")
        ]
    }

    private func xcodeLines(_ group: CrashGroup) -> [String] {
        let count = group.xcode.count
        return [
            "    xcode: \(count) crash\(count == 1 ? "" : "es")",
            "      " + group.xcode.map(\.event.id).joined(separator: ", ")
        ]
    }

    private func metricsDescription(events: Int?, users: Int?) -> String {
        if events == nil && users == nil { return "" }
        let eventsText = events.map(String.init) ?? "?"
        let usersText = users.map(String.init) ?? "?"
        return "\(eventsText) events / \(usersText) users"
    }
}
