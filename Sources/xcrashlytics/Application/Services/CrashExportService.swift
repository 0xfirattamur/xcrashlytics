import Foundation

struct CrashExportService: Sendable {
    let details: CrashDetailService
    let clients: CrashlyticsClientProvider
    let reportWriter: ReportWriter
    let dateProvider: DateProvider

    // MARK: - Public API

    func export(_ request: CrashExportRequest) async throws -> CrashExportResult {
        let now = dateProvider.currentDate()
        // Parsed before any request so bad input fails fast.
        let window = try ReportWindow(since: request.since, now: now).interval
        let detailRequest = CrashDetailRequest(
            id: request.id,
            frameFilter: request.frameFilter,
            crashDirectories: request.crashDirectories,
            impactWindow: window)
        let detail = try await details.detail(detailRequest)

        var result = CrashExportResult(detail: detail, exportedAt: now, window: window, warnings: detail.warnings)
        guard let issue = detail.issue, detail.event.source == .firebase else { return result }

        let target = try IssueReportTarget.resolve(request.id, clients: clients)
        let loaded = try await loadSpreads(issueId: issue.providerId, window: window, client: target.client)
        result.spreads = loaded.spreads.isEmpty ? nil : loaded.spreads
        result.versionRange = loaded.spreads.versions.flatMap(VersionRange.init)
        result.warnings += loaded.warnings
        return result
    }

    func write(_ report: String, to path: String) throws -> String {
        try reportWriter.write(report, to: path)
    }

    // MARK: - Breakdown spreads

    private struct LoadedSpreads {
        var spreads: CrashSpreads
        var warnings: [CommandWarning]
    }

    /// A dimension whose report fails stays nil and yields a warning.
    private func loadSpreads(
        issueId: String, window: DateInterval, client: CrashlyticsClient
    ) async throws -> LoadedSpreads {
        async let versions = Self.load(.version, issueId: issueId, window: window, client: client)
        async let systems = Self.load(.os, issueId: issueId, window: window, client: client)
        async let devices = Self.load(.device, issueId: issueId, window: window, client: client)
        let results = await [versions, systems, devices]
        try Task.checkCancellation()

        var warnings: [CommandWarning] = []
        var rows: [BreakdownDimension: [BreakdownRow]] = [:]
        for (dimension, result) in zip(BreakdownDimension.allCases, results) {
            switch result {
            case .success(let loaded):
                rows[dimension] = loaded
            case .failure(let error):
                let reason = FailureMapper.failure(for: error).message
                warnings.append(CommandWarning(
                    code: .breakdownUnavailable,
                    message: "the \(dimension.rawValue) report failed (\(reason)); "
                        + "its 'Where it happens' spread comes from the newest sampled events."))
            }
        }
        let spreads = CrashSpreads(
            window: window, versions: rows[.version], operatingSystems: rows[.os], devices: rows[.device])
        return LoadedSpreads(spreads: spreads, warnings: warnings)
    }

    private static func load(
        _ dimension: BreakdownDimension, issueId: String, window: DateInterval, client: CrashlyticsClient
    ) async -> Result<[BreakdownRow], Error> {
        do {
            return .success(try await client.fetchBreakdown(issueId: issueId, dimension: dimension, interval: window))
        } catch {
            return .failure(error)
        }
    }
}
