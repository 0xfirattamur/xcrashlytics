import Foundation
@testable import xcrashlytics

/// Scripted `HTTPClient` for tests.
///
/// Tests provide a handler that maps `URLRequest` to a canned `(Data, HTTPURLResponse)`
/// or throws. A history of every dispatched request is kept for assertions.
/// The handler runs outside the lock, so concurrent requests really overlap;
/// handlers that touch shared state should use `AtomicCounter` or their own lock.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
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
        lock.withLock { recordedRequests.append(request) }
        guard let handler else {
            throw HTTPTransportError.transport("no handler set on FakeHTTPClient")
        }
        return try handler(request)
    }

    /// Convenience for building a JSON response from a `Data` body.
    static func response(_ url: URL, status: Int, body: Data, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        let stubResponse = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, stubResponse)
    }
}

/// A counter safe to bump from concurrent handlers.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Increments and returns the new value.
    @discardableResult
    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }

    var value: Int { lock.withLock { count } }
}
