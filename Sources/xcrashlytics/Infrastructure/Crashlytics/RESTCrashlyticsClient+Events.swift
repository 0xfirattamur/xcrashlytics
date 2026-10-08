import Foundation

extension RESTCrashlyticsClient {
    // Crashlytics quirk: without an interval the API returns only the last ~7 days, so it is always sent.
    func fetchEvents(
        issueId: String, pageSize: Int = 100, limit: Int? = nil, interval: DateInterval
    ) async throws -> [CrashlyticsEvent] {
        try Self.validateIssueId(issueId)
        if let limit, limit <= 0 { return [] }
        let effectivePageSize = limit.map { min($0, pageSize) } ?? pageSize
        var pageToken: String?
        var events: [CrashlyticsEvent] = []
        for _ in 0..<Self.maxPages {
            let response = try await fetchEventsPage(
                issueId: issueId,
                pageToken: pageToken,
                pageSize: effectivePageSize,
                interval: interval
            )
            events.append(contentsOf: response.events.map(eventMapper.event(from:)))
            if let limit, events.count >= limit {
                return Array(events.prefix(limit))
            }
            guard let nextToken = Self.nextPageToken(response.nextPageToken, after: pageToken) else { break }
            pageToken = nextToken
        }
        return events
    }

    private func fetchEventsPage(
        issueId: String,
        pageToken: String?,
        pageSize: Int,
        interval: DateInterval
    ) async throws -> CrashlyticsDTO.EventsResponse {
        var query = Self.intervalQuery(interval)
        query.append(URLQueryItem(name: "filter.issue.id", value: issueId))
        query.append(URLQueryItem(name: "page_size", value: String(pageSize)))
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }
        let data = try await get(path: "events", query: query, resource: .events(issueId))
        do {
            return try CrashlyticsDTO.EventsResponse.decodePreservingRawEvents(from: data)
        } catch {
            throw CrashlyticsClientError.decodingFailed("events of issue \(issueId): \(CrashlyticsDTO.describe(error))")
        }
    }
}
