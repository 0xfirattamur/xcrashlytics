struct IssuesPresenter: CommandPresenter {
    var encoder = JSONPayloadEncoder()
    var text = IssuesTextRenderer()

    func render(_ result: IssueSearchResult, format: OutputFormat) throws -> RenderedOutput {
        let body: String
        switch format {
        case .text:
            body = textBody(result)
        case .json:
            body = try encoder.envelope(payload(result), warnings: result.warnings)
        case .ndjson:
            body = try encoder.ndjson(ndjsonRecords(result))
        }
        return RenderedOutput(body: body, warnings: result.warnings)
    }

    // MARK: - Formats

    private func textBody(_ result: IssueSearchResult) -> String {
        text.render(
            issues: result.issues,
            xcodeCrashes: result.xcodeCrashes,
            hint: result.hint,
            symbolicationHint: result.symbolicationHint,
            lastSeenAt: result.lastSeenAt)
    }

    private func ndjsonRecords(_ result: IssueSearchResult) -> [IssuesRecord] {
        var records = issueSummaries(result).map(IssuesRecord.issue)
        records += result.xcodeCrashes.map { .xcodeCrash(XcodeIssueSummary($0)) }
        if result.hint != nil || result.symbolicationHint != nil {
            records.append(.hint(result.hint, symbolicationHint: result.symbolicationHint))
        }
        return records
    }

    private func issueSummaries(_ result: IssueSearchResult) -> [IssueSummary] {
        result.issues.map { IssueSummary($0, lastSeenAt: result.lastSeenAt[$0.id]) }
    }

    private func payload(_ result: IssueSearchResult) -> IssuesPayload {
        let request = result.request
        let criteria = request.criteria
        let xcodeSummaries = result.xcodeCrashes.map(XcodeIssueSummary.init)
        let relatedGroups = RelatedIssueGrouper.build(firebase: result.issues, xcode: result.xcodeCrashes)
        return IssuesPayload(
            query: criteria.query,
            match: criteria.match,
            limit: request.limit,
            searchLimit: result.fetchLimit,
            fetchedIssuesCount: result.fetchedCount,
            matchedIssuesCount: result.matchedCount,
            hint: result.hint,
            appVersion: criteria.appVersion,
            sinceVersion: criteria.sinceVersion,
            matchedVersions: result.matchedVersions,
            file: criteria.file,
            symbol: criteria.symbol,
            since: request.since,
            window: ReportWindowSummary(result.window),
            domain: criteria.domain,
            userInfoKey: criteria.userInfoKey.nilIfEmpty,
            eventMetadataSamples: result.eventMetadataSamples > 0 ? result.eventMetadataSamples : nil,
            symbolicationHint: result.symbolicationHint,
            issues: issueSummaries(result),
            xcodeCrashes: request.includesXcode ? xcodeSummaries : nil,
            matchedXcodeCrashesCount: request.includesXcode ? result.matchedXcodeCount : nil,
            relatedGroups: relatedGroups.nilIfEmpty?.map(RelatedIssueGroupPayload.init))
    }
}
