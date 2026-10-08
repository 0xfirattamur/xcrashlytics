import Foundation

extension RESTCrashlyticsClient {
    func sendWithRetry(_ originalRequest: URLRequest, resource: Resource) async throws -> Data {
        var state = RetryState()
        while true {
            try Task.checkCancellation()
            let token = try await tokens.token()
            let request = Self.authorized(originalRequest, token: token)

            switch try await perform(request) {
            case .transportFailure(let message):
                try await backOffAfterTransportFailure(message, state: &state)
            case .response(let data, let response):
                switch try disposition(of: response, data: data, resource: resource, state: state) {
                case .done:
                    return data
                case .refreshToken:
                    state.refreshed = true
                    _ = try await tokens.forceRefresh(rejecting: token)
                case .retry:
                    try await backOff(state.retries, response: response)
                    state.retries += 1
                }
            }
        }
    }

    // MARK: - Types

    private struct RetryState {
        var refreshed = false
        var retries = 0
    }

    private enum Attempt {
        case response(Data, HTTPURLResponse)
        case transportFailure(String)
    }

    private enum Disposition {
        case done, refreshToken, retry
    }

    // MARK: - Attempts

    private static func authorized(_ request: URLRequest, token: String) -> URLRequest {
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    private func perform(_ request: URLRequest) async throws -> Attempt {
        do {
            let (data, response) = try await httpClient.send(request)
            return .response(data, response)
        } catch HTTPTransportError.cancelled {
            throw CancellationError()
        } catch let error as CancellationError {
            throw error
        } catch {
            return .transportFailure(Self.transportMessage(error))
        }
    }

    private func backOffAfterTransportFailure(_ message: String, state: inout RetryState) async throws {
        let maxTransportRetries = min(retryPolicy.maxRetries, retryPolicy.maxTransportRetries)
        guard state.retries < maxTransportRetries else {
            throw CrashlyticsClientError.network(message)
        }
        try await sleeper.sleep(seconds: retryPolicy.backoff(attempt: state.retries))
        state.retries += 1
    }

    // MARK: - Response handling

    private func disposition(
        of response: HTTPURLResponse,
        data: Data,
        resource: Resource,
        state: RetryState
    ) throws -> Disposition {
        let retries = state.retries
        let status = response.statusCode
        switch status {
        case 200..<300:
            return .done
        case 401:
            guard !state.refreshed else {
                throw CrashlyticsClientError.unauthorized(
                    Self.describe("Google rejected the refreshed access token (401)", data: data))
            }
            return .refreshToken
        case 403:
            throw CrashlyticsClientError.permissionDenied(
                Self.describe("The signed-in Google account cannot read this Crashlytics app (403)", data: data))
        case 404:
            throw CrashlyticsClientError.notFound(notFoundMessage(resource))
        case 429:
            guard retries < retryPolicy.maxRetries else { throw CrashlyticsClientError.rateLimited(retries: retries) }
            return .retry
        case 500, 502, 503, 504:
            guard retries < retryPolicy.maxRetries else {
                throw CrashlyticsClientError.apiError(code: status, message: Self.apiMessage(data))
            }
            return .retry
        default:
            throw CrashlyticsClientError.apiError(code: status, message: Self.apiMessage(data))
        }
    }

    // MARK: - Backoff and messages

    private func backOff(_ attempt: Int, response: HTTPURLResponse) async throws {
        let delay = retryPolicy.delay(
            attempt: attempt,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
            now: dateProvider.currentDate())
        try await sleeper.sleep(seconds: delay)
    }

    private func notFoundMessage(_ resource: Resource) -> String {
        switch resource {
        case .app:
            return "Crashlytics app \(appId) was not found in project \(projectNumber); check the app id in the config."
        case .issue(let id):
            return "issue \(id) was not found in this app; check the issue id."
        case .events(let id):
            return "events for issue \(id) were not found; the issue or the app does not exist."
        }
    }

    private static func transportMessage(_ error: Error) -> String {
        if case HTTPTransportError.transport(let message) = error { return message }
        return error.localizedDescription
    }

    private static func googleMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return nil }
        return (error["message"] as? String)?.trimmedNonEmpty
    }

    private static func apiMessage(_ data: Data) -> String {
        if let message = googleMessage(data) { return message }
        guard let text = String(data: data, encoding: .utf8)?.trimmedNonEmpty else {
            return "the response had no readable body."
        }
        return String(text.prefix(200))
    }

    private static func describe(_ summary: String, data: Data) -> String {
        googleMessage(data).map { "\(summary): \($0)" } ?? "\(summary)."
    }
}
