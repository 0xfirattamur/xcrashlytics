import Foundation

extension RESTCrashlyticsClient {
    func fetchReportedVersions(interval: DateInterval) async throws -> [ReportedVersion] {
        var pageToken: String?
        var versions: [ReportedVersion] = []
        for _ in 0..<Self.maxPages {
            let response = try await fetchTopVersionsPage(
                pageToken: pageToken, extraQuery: Self.intervalQuery(interval))
            versions += response.groups.compactMap { $0.version.flatMap(reportMapper.reportedVersion(from:)) }
            guard let nextToken = Self.nextPageToken(response.nextPageToken, after: pageToken) else { break }
            pageToken = nextToken
        }
        return versions
    }

    // Crashlytics quirk: topIssues rejects `filter.issue.id`, so use topVersions, which reports a
    // series per version; days are summed across versions.
    func fetchDailyEventCounts(issueId: String, interval: DateInterval) async throws -> [DailyEventCount] {
        try Self.validateIssueId(issueId)
        var query = Self.intervalQuery(interval)
        query.append(URLQueryItem(name: "filter.issue.id", value: issueId))
        query.append(URLQueryItem(name: "granularity", value: "TIME_GRANULARITY_DAY"))
        var pageToken: String?
        var perDay: [String: Int] = [:]
        for _ in 0..<Self.maxPages {
            let response = try await fetchTopVersionsPage(pageToken: pageToken, extraQuery: query)
            for group in response.groups {
                for point in reportMapper.dailyEvents(from: group.metrics) {
                    perDay[point.day, default: 0] += point.eventsCount
                }
            }
            guard let nextToken = Self.nextPageToken(response.nextPageToken, after: pageToken) else { break }
            pageToken = nextToken
        }
        return perDay.map { DailyEventCount(day: $0.key, eventsCount: $0.value) }.sorted { $0.day < $1.day }
    }

    private func fetchTopVersionsPage(
        pageToken: String?,
        extraQuery: [URLQueryItem]
    ) async throws -> CrashlyticsDTO.TopVersionsResponse {
        var query = extraQuery
        query.append(URLQueryItem(name: "page_size", value: "100"))
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }
        let data = try await get(path: "reports/topVersions", query: query, resource: .app)
        do {
            return try JSONDecoder().decode(CrashlyticsDTO.TopVersionsResponse.self, from: data)
        } catch {
            throw CrashlyticsClientError.decodingFailed("top versions report: \(CrashlyticsDTO.describe(error))")
        }
    }

    func fetchBreakdown(
        issueId: String?, dimension: BreakdownDimension, interval: DateInterval
    ) async throws -> [BreakdownRow] {
        var query = Self.intervalQuery(interval)
        if let issueId {
            try Self.validateIssueId(issueId)
            query.append(URLQueryItem(name: "filter.issue.id", value: issueId))
        }
        var pageToken: String?
        var rows: [BreakdownRow] = []
        for _ in 0..<Self.maxPages {
            let page = try await fetchReportPage(dimension: dimension, pageToken: pageToken, extraQuery: query)
            for group in page.groups {
                rows += reportMapper.breakdownRows(from: group, dimension: dimension, issueScoped: issueId != nil)
            }
            guard let nextToken = Self.nextPageToken(page.nextPageToken, after: pageToken) else { break }
            pageToken = nextToken
        }
        return reportMapper.ranked(rows)
    }

    private func fetchReportPage(
        dimension: BreakdownDimension,
        pageToken: String?,
        extraQuery: [URLQueryItem]
    ) async throws -> CrashlyticsDTO.BreakdownReportResponse {
        let (path, label): (String, String) = switch dimension {
        case .version: ("reports/topVersions", "top versions report")
        case .os: ("reports/topOperatingSystems", "top operating systems report")
        case .device: ("reports/topAppleDevices", "top devices report")
        }
        var query = extraQuery
        query.append(URLQueryItem(name: "page_size", value: "100"))
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }
        let data = try await get(path: path, query: query, resource: .app)
        do {
            return try JSONDecoder().decode(CrashlyticsDTO.BreakdownReportResponse.self, from: data)
        } catch {
            throw CrashlyticsClientError.decodingFailed("\(label): \(CrashlyticsDTO.describe(error))")
        }
    }
}
