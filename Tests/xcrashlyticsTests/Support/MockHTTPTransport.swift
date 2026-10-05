import Foundation
@testable import xcrashlytics

/// Scripted `HTTPTransport` for tests.
///
/// Tests provide a handler that maps `URLRequest` to a canned `(Data, HTTPURLResponse)`
/// or throws. A history of every dispatched request is kept for assertions.
final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    let handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    init(handler: ((URLRequest) throws -> (Data, HTTPURLResponse))? = nil) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Scripted handlers can capture mutable counters; serialize them with the history.
        try lock.withLock {
            recordedRequests.append(request)
            guard let handler else {
                throw HTTPError.transport("no handler set on MockHTTPTransport")
            }
            return try handler(request)
        }
    }

    /// Convenience for building a JSON response from a `Data` body.
    static func response(_ url: URL, status: Int, body: Data, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, resp)
    }
}
