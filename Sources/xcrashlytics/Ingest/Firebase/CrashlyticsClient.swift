//
//  FirebaseClient.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// The Crashlytics operations commands and processing depend on.
protocol CrashlyticsAPI: Sendable {
    func listIssues(maxIssues: Int?) async throws -> [CrashIssue]
    func representativeFrames(issueID: String) async throws -> [Frame]
    func listEvents(issueID: String, maxEvents: Int?) async throws -> [FirebaseEvent]
    func getIssueDetail(id: String) async throws -> CrashIssue
}

/// How many newest events commands sample when inspecting a single issue.
enum FirebaseEventSampling {
    static let limit = 100
}

/// Client for the Firebase Crashlytics `v1alpha` REST API.
///
/// Requests are scoped by the numeric project number embedded in the app id
/// (`1:<number>:<platform>:<hash>`), not by the project slug.
struct CrashlyticsClient: Sendable {
    private let httpTransport: HTTPTransport
    private let tokens: AccessTokenProvider
    private let sleeper: Sleeper
    private let projectNumber: String
    private let appId: String
    private let baseURL: URL
    private let maxRetries: Int

    init(
        httpTransport: HTTPTransport,
        tokens: AccessTokenProvider,
        sleeper: Sleeper,
        appId: String,
        baseURL: URL = URL(string: "https://firebasecrashlytics.googleapis.com")!,
        maxRetries: Int = 5
    ) throws {
        guard let number = Self.projectNumber(fromAppId: appId) else {
            throw FirebaseError.apiError(
                code: -1,
                message: "could not extract project number from appId '\(appId)' (expected '1:<number>:<platform>:<hash>')."
            )
        }
        guard appId.unicodeScalars.allSatisfy({ Self.appIdAllowedCharacters.contains($0) }) else {
            throw FirebaseError.invalidRequest("app id '\(appId)' contains unsupported characters.")
        }
        self.httpTransport = httpTransport
        self.tokens = tokens
        self.sleeper = sleeper
        self.projectNumber = number
        self.appId = appId
        self.baseURL = baseURL
        self.maxRetries = maxRetries
    }

    init(
        appId: String,
        fileSystem: FileSystem,
        httpTransport: HTTPTransport = URLSessionHTTPTransport()
    ) throws {
        try self.init(
            httpTransport: httpTransport,
            tokens: FirebaseToolsTokenProvider(fs: fileSystem, httpTransport: httpTransport),
            sleeper: TaskSleeper(),
            appId: appId
        )
    }

    /// Extracts the numeric project ID from an `appId` of form `1:<number>:<platform>:<hash>`.
    static func projectNumber(fromAppId appId: String) -> String? {
        let parts = appId.split(separator: ":")
        guard parts.count >= 4, let n = UInt64(parts[1]) else { return nil }
        return String(n)
    }

    /// Lists top crashes from `reports/topIssues` (impact-ordered).
    ///
    /// With `maxIssues` set, paging stops as soon as that many issues are
    /// collected — so `--limit N` fetches roughly one small page instead of the
    /// whole project. Leave it `nil` for grouping or blame aggregation to fetch all,
    /// since clustering needs the complete set.
    func listIssues(pageSize: Int = 100, maxIssues: Int? = nil) async throws -> [CrashIssue] {
        let effectivePageSize = maxIssues.map { min($0, pageSize) } ?? pageSize
        var pageToken: String?
        var out: [CrashIssue] = []
        repeat {
            let resp = try await fetchTopIssuesPage(pageToken: pageToken, pageSize: effectivePageSize)
            for group in resp.groups ?? [] {
                let m = group.metrics?.first
                let issue = group.issue.toCrashIssue(
                    eventsCount: m?.eventsCount.flatMap(Int.init),
                    impactedUsersCount: m?.impactedUsersCount.flatMap(Int.init)
                )
                out.append(issue)
            }
            pageToken = resp.nextPageToken
            if let maxIssues, out.count >= maxIssues {
                return Array(out.prefix(maxIssues))
            }
        } while pageToken != nil
        return out
    }

    /// Fetches the representative event's stack frames for an issue, so a
    /// frame-level cross-source match is possible. Returns `[]` if the issue
    /// has no retrievable event. The issue endpoints only return summaries —
    /// frames live on events.
    func representativeFrames(issueID: String) async throws -> [Frame] {
        try await listEvents(issueID: issueID, maxEvents: 1).first?.representativeFrames() ?? []
    }

    /// Lists Firebase events for a single issue.
    func listEvents(issueID: String, pageSize: Int = 100, maxEvents: Int? = nil) async throws -> [FirebaseEvent] {
        try Self.validateIssueId(issueID)
        let effectivePageSize = maxEvents.map { min($0, pageSize) } ?? pageSize
        var pageToken: String?
        var out: [FirebaseEvent] = []
        repeat {
            let resp = try await fetchEventsPage(
                issueID: issueID,
                pageToken: pageToken,
                pageSize: effectivePageSize
            )
            out.append(contentsOf: (resp.events ?? []).map { $0.toFirebaseEvent() })
            pageToken = resp.nextPageToken
            if let maxEvents, out.count >= maxEvents {
                return Array(out.prefix(maxEvents))
            }
        } while pageToken != nil
        return out
    }

    /// Fetches a single issue's detail.
    func getIssueDetail(id: String) async throws -> CrashIssue {
        try Self.validateIssueId(id)
        let data = try await get(path: "issues/\(id)", query: [:])
        let dto: FirebaseDTO.IssueDTO
        do {
            dto = try JSONDecoder().decode(FirebaseDTO.IssueDTO.self, from: data)
        } catch {
            throw FirebaseError.decodingFailed("issue detail: \(error)")
        }
        return dto.toCrashIssue()
    }

    // MARK: - Internal

    private func fetchTopIssuesPage(pageToken: String?, pageSize: Int) async throws -> FirebaseDTO.TopIssuesResponse {
        var query: [String: String] = ["page_size": String(pageSize)]
        if let pageToken { query["page_token"] = pageToken }
        let data = try await get(path: "reports/topIssues", query: query)
        do {
            return try JSONDecoder().decode(FirebaseDTO.TopIssuesResponse.self, from: data)
        } catch {
            throw FirebaseError.decodingFailed("topIssues: \(error)")
        }
    }

    private func fetchEventsPage(
        issueID: String,
        pageToken: String?,
        pageSize: Int
    ) async throws -> FirebaseDTO.EventsResponse {
        var query: [String: String] = [
            "filter.issue.id": issueID,
            "page_size": String(pageSize)
        ]
        if let pageToken { query["page_token"] = pageToken }
        let data = try await get(path: "events", query: query)
        do {
            return try FirebaseDTO.EventsResponse.decodePreservingRawEvents(from: data)
        } catch {
            throw FirebaseError.decodingFailed("events: \(error)")
        }
    }

    private static let idAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Allowlist for the full appId string. Google app IDs (`1:<digits>:<platform>:<hash>`)
    /// only contain alphanumerics, colons, underscores, and hyphens — never `/`, `.`, `%`, or spaces.
    private static let appIdAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:_-")

    private static func validateIssueId(_ value: String) throws {
        guard !value.isEmpty else {
            throw FirebaseError.invalidRequest("issue id must not be empty.")
        }
        guard value.unicodeScalars.allSatisfy({ idAllowedCharacters.contains($0) }) else {
            throw FirebaseError.invalidRequest("issue id '\(value)' contains unsupported characters.")
        }
    }

    private func buildURL(path: String, query: [String: String]) throws -> URL {
        let full = "\(baseURL.absoluteString)/v1alpha/projects/\(projectNumber)/apps/\(appId)/\(path)"
        guard var comp = URLComponents(string: full) else {
            throw FirebaseError.invalidRequest("could not build request URL for path '\(path)'.")
        }
        if !query.isEmpty {
            comp.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comp.url else {
            throw FirebaseError.invalidRequest("could not build request URL for path '\(path)'.")
        }
        return url
    }

    private func get(path: String, query: [String: String]) async throws -> Data {
        var req = URLRequest(url: try buildURL(path: path, query: query))
        req.httpMethod = "GET"
        return try await sendWithRetry(req)
    }

    private func sendWithRetry(_ originalRequest: URLRequest) async throws -> Data {
        var didRefresh = false
        var attempt = 0
        while true {
            var req = originalRequest
            let token = try await tokens.token()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await httpTransport.send(req)
            } catch let e as HTTPError {
                throw FirebaseError.apiError(code: -1, message: "\(e)")
            }

            switch response.statusCode {
            case 200..<300:
                return data
            case 401 where !didRefresh:
                didRefresh = true
                _ = try await tokens.forceRefresh()
                continue
            case 429, 503:
                if attempt >= maxRetries {
                    throw FirebaseError.rateLimited(retries: attempt)
                }
                let delay = min(pow(2.0, Double(attempt)), 60.0)
                try? await sleeper.sleep(seconds: delay)
                attempt += 1
                continue
            default:
                let message = String(data: data, encoding: .utf8) ?? "<binary>"
                throw FirebaseError.apiError(code: response.statusCode, message: message)
            }
        }
    }
}

extension CrashlyticsClient: CrashlyticsAPI {
    func listIssues(maxIssues: Int?) async throws -> [CrashIssue] {
        try await listIssues(pageSize: 100, maxIssues: maxIssues)
    }

    func listEvents(issueID: String, maxEvents: Int?) async throws -> [FirebaseEvent] {
        try await listEvents(issueID: issueID, pageSize: 100, maxEvents: maxEvents)
    }
}
