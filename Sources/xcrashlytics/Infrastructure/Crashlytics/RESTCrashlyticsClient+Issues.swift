import Foundation

extension RESTCrashlyticsClient {
    // A `limit` stops paging early; grouping and blame aggregation pass nil because they need every issue.
    // Crashlytics quirk: without an interval the API counts the previous 7 days.
    func fetchIssues(
        pageSize: Int = 100, limit: Int? = nil, interval: DateInterval? = nil,
        options: IssueQueryOptions = IssueQueryOptions()
    ) async throws -> [CrashIssue] {
        if let limit, limit <= 0 { return [] }
        let effectivePageSize = limit.map { min($0, pageSize) } ?? pageSize
        let extraQuery = Self.intervalQuery(interval) + Self.optionsQuery(options)
        var pageToken: String?
        var issues: [CrashIssue] = []
        for _ in 0..<Self.maxPages {
            let response = try await fetchTopIssuesPage(
                pageToken: pageToken, pageSize: effectivePageSize, extraQuery: extraQuery)
            for group in response.groups {
                let metrics = group.metrics.first
                issues.append(issueMapper.issue(
                    from: group.issue,
                    eventsCount: metrics?.eventsCount?.intValue,
                    impactedUsersCount: metrics?.impactedUsersCount?.intValue,
                    dailyEvents: options.includesDailyCounts ? reportMapper.dailyEvents(from: group.metrics) : nil
                ))
            }
            if let limit, issues.count >= limit {
                return Array(issues.prefix(limit))
            }
            guard let nextToken = Self.nextPageToken(response.nextPageToken, after: pageToken) else { break }
            pageToken = nextToken
        }
        return issues
    }

    func fetchIssue(id: String) async throws -> CrashIssue {
        try Self.validateIssueId(id)
        let data = try await get(path: "issues/\(id)", query: [], resource: .issue(id))
        let issueDTO: CrashlyticsDTO.Issue
        do {
            issueDTO = try JSONDecoder().decode(CrashlyticsDTO.Issue.self, from: data)
        } catch {
            throw CrashlyticsClientError.decodingFailed("issue \(id): \(CrashlyticsDTO.describe(error))")
        }
        return issueMapper.issue(from: issueDTO)
    }

    // Crashlytics quirk: `reports/topIssues` rejects `filter.issue.id` (400) and summing per-variant
    // reports overcounts users, so page the top issues until this one appears. Out of pages means
    // no events in the window; nil means it ranks below `maxPages` pages.
    func fetchIssueImpact(issueId: String, since: Date, until: Date, maxPages: Int) async throws -> IssueImpact? {
        try Self.validateIssueId(issueId)
        let interval = Self.intervalQuery(DateInterval(start: since, end: until))
        var pageToken: String?
        var appUsers: Int?
        for _ in 0..<max(1, maxPages) {
            let response = try await fetchTopIssuesPage(pageToken: pageToken, pageSize: 100, extraQuery: interval)
            for group in response.groups {
                let metrics = group.metrics.first
                appUsers = appUsers ?? metrics?.totalUsersCount?.intValue
                guard group.issue.id == issueId else { continue }
                return IssueImpact(
                    since: since,
                    until: until,
                    eventsCount: metrics?.eventsCount?.intValue ?? 0,
                    impactedUsersCount: metrics?.impactedUsersCount?.intValue ?? 0,
                    appUsersCount: appUsers
                )
            }
            pageToken = response.nextPageToken?.trimmedNonEmpty
            if pageToken == nil {
                return IssueImpact(
                    since: since, until: until, eventsCount: 0, impactedUsersCount: 0, appUsersCount: appUsers)
            }
        }
        return nil
    }

    private static func optionsQuery(_ options: IssueQueryOptions) -> [URLQueryItem] {
        var items = options.versionDisplayNames.map { URLQueryItem(name: "filter.version.displayNames", value: $0) }
        if options.includesDailyCounts {
            items.append(URLQueryItem(name: "granularity", value: "TIME_GRANULARITY_DAY"))
        }
        return items
    }

    private func fetchTopIssuesPage(
        pageToken: String?,
        pageSize: Int,
        extraQuery: [URLQueryItem] = []
    ) async throws -> CrashlyticsDTO.TopIssuesResponse {
        var query = extraQuery
        query.append(URLQueryItem(name: "page_size", value: String(pageSize)))
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }
        let data = try await get(path: "reports/topIssues", query: query, resource: .app)
        do {
            return try JSONDecoder().decode(CrashlyticsDTO.TopIssuesResponse.self, from: data)
        } catch {
            throw CrashlyticsClientError.decodingFailed("top issues report: \(CrashlyticsDTO.describe(error))")
        }
    }
}
