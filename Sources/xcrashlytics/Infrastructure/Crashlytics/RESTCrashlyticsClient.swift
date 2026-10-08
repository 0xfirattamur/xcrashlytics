import Foundation

// Crashlytics quirk: requests are scoped by the numeric project number embedded in the app id
// (`1:<number>:<platform>:<hash>`), not by the project slug.
struct RESTCrashlyticsClient: Sendable {
    let httpClient: HTTPClient
    let tokens: AccessTokenProvider
    let sleeper: Sleeper
    let dateProvider: DateProvider
    let projectNumber: String
    let appId: String
    let baseURL: URL
    let retryPolicy: RetryPolicy
    let issueMapper = CrashlyticsIssueMapper()
    let eventMapper = CrashlyticsEventDTOMapper()
    let reportMapper = CrashlyticsReportMapper()

    // Bounds paging so a server that keeps returning page tokens cannot loop the client forever.
    static let maxPages = 100

    init(
        httpClient: HTTPClient,
        tokens: AccessTokenProvider,
        sleeper: Sleeper,
        appId: String,
        baseURL: URL = URL(string: "https://firebasecrashlytics.googleapis.com")!,
        maxRetries: Int = 5,
        jitter: @escaping @Sendable () -> Double = RetryPolicy.randomJitter,
        dateProvider: DateProvider = SystemDateProvider()
    ) throws {
        guard let number = FirebaseAppId.projectNumber(from: appId),
              appId.unicodeScalars.allSatisfy({ Self.appIdAllowedCharacters.contains($0) })
        else {
            throw ConfigError.invalidAppId(appId)
        }
        self.httpClient = httpClient
        self.tokens = tokens
        self.sleeper = sleeper
        self.dateProvider = dateProvider
        self.projectNumber = number
        self.appId = appId
        self.baseURL = baseURL
        self.retryPolicy = RetryPolicy(maxRetries: maxRetries, jitter: jitter)
    }

    init(
        appId: String,
        fileStore: FileStore,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        dateProvider: DateProvider = SystemDateProvider()
    ) throws {
        let tokenProvider = FirebaseToolsTokenProvider(
            fileStore: fileStore, httpClient: httpClient, dateProvider: dateProvider)
        try self.init(
            httpClient: httpClient,
            tokens: tokenProvider,
            sleeper: TaskSleeper(),
            appId: appId,
            dateProvider: dateProvider
        )
    }

    // Paging is over when the server sends no token, an empty one, or the one just used.
    static func nextPageToken(_ token: String?, after previous: String?) -> String? {
        guard let token = token?.trimmedNonEmpty, token != previous else { return nil }
        return token
    }

    static func intervalQuery(_ interval: DateInterval?) -> [URLQueryItem] {
        guard let interval else { return [] }
        let timestamp = ISO8601DateFormatter()
        return [
            URLQueryItem(name: "filter.interval.startTime", value: timestamp.string(from: interval.start)),
            URLQueryItem(name: "filter.interval.endTime", value: timestamp.string(from: interval.end))
        ]
    }

    private static let idAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    // The app id is interpolated into the URL path: allow only what Google app ids contain,
    // never `/`, `.`, `%`, or spaces.
    private static let appIdAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:_-")

    static func validateIssueId(_ value: String) throws {
        guard !value.isEmpty else {
            throw CrashlyticsClientError.invalidRequest("issue id must not be empty.")
        }
        guard value.unicodeScalars.allSatisfy({ idAllowedCharacters.contains($0) }) else {
            throw CrashlyticsClientError.invalidRequest("issue id '\(value)' contains unsupported characters.")
        }
    }

    enum Resource {
        case app
        case issue(String)
        case events(String)
    }

    private func buildURL(path: String, query: [URLQueryItem]) throws -> URL {
        let urlString = "\(baseURL.absoluteString)/v1alpha/projects/\(projectNumber)/apps/\(appId)/\(path)"
        guard var components = URLComponents(string: urlString) else {
            throw CrashlyticsClientError.invalidRequest("could not build request URL for path '\(path)'.")
        }
        if !query.isEmpty {
            // Sorted by name, then value, so requests are deterministic; repeated names stay repeated.
            components.percentEncodedQueryItems = query
                .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
                .map {
                    URLQueryItem(
                        name: FormURLEncoder.encodeQuery($0.name),
                        value: $0.value.map(FormURLEncoder.encodeQuery))
                }
        }
        guard let url = components.url else {
            throw CrashlyticsClientError.invalidRequest("could not build request URL for path '\(path)'.")
        }
        return url
    }

    func get(path: String, query: [URLQueryItem], resource: Resource) async throws -> Data {
        var request = URLRequest(url: try buildURL(path: path, query: query))
        request.httpMethod = "GET"
        return try await sendWithRetry(request, resource: resource)
    }
}

extension RESTCrashlyticsClient: CrashlyticsClient {
    func fetchIssues(limit: Int?, interval: DateInterval?, options: IssueQueryOptions) async throws -> [CrashIssue] {
        try await fetchIssues(pageSize: 100, limit: limit, interval: interval, options: options)
    }

    func fetchEvents(issueId: String, limit: Int?, interval: DateInterval) async throws -> [CrashlyticsEvent] {
        try await fetchEvents(issueId: issueId, pageSize: 100, limit: limit, interval: interval)
    }
}
