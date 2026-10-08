struct InitTextRenderer: Sendable {
    func render(_ result: InitResult) -> String {
        var lines = discoveryLines(result)
        lines += result.checks.compactMap(line(for:))
        lines += outcomeLines(result)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Discovery

    private func discoveryLines(_ result: InitResult) -> [String] {
        var lines: [String] = []
        if !result.discovered.isEmpty {
            lines.append("Found \(result.discovered.count) Firebase app(s):")
            lines += result.discovered.map(appLine)
        }
        if !result.libraries.isEmpty {
            let libraries = result.libraries.joined(separator: ", ")
            lines.append("First-party libraries: \(libraries) (frames count as app frames)")
        }
        return lines
    }

    private func appLine(_ app: DiscoveredFirebaseApp) -> String {
        let bundleId = app.bundleId ?? "-"
        let line = "  \(app.profileName)   \(app.platform)   \(app.appId)   \(bundleId)   (\(app.sourcePath))"
        guard let hostApp = app.extensionOf else { return line }
        return line + "   extension of \(hostApp)"
    }

    // MARK: - Checks

    private func line(for check: SetupCheck) -> String? {
        switch check {
        case .ok:
            return nil
        case .warn(let message):
            return "[WARN] \(message)"
        case .fail(let message, let hint):
            let hintLines = hint.map { "          \($0)" }
            return (["[FAIL] \(message)"] + hintLines).joined(separator: "\n")
        }
    }

    // MARK: - Outcome

    private func outcomeLines(_ result: InitResult) -> [String] {
        switch result.outcome {
        case .blocked:
            return ["Some checks failed. Fix the above, then re-run `xcrashlytics init`."]
        case let .written(activeProfile):
            return [
                result.hasWarnings ? "Setup OK — warnings above are advisory." : "All checks passed.",
                ".xcrashlytics.json written. It holds app ids only, no secrets"
                    + " — commit it so the team shares the setup.",
                activeProfileLine(activeProfile)
            ]
        }
    }

    private func activeProfileLine(_ activeProfile: String?) -> String {
        guard let activeProfile else {
            return "No active profile yet — pick one: xcrashlytics use <profile>"
        }
        return "Active profile: \(activeProfile)."
    }
}
