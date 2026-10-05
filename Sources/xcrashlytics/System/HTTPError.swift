import Foundation

/// Errors raised by `HTTPTransport` implementations.
enum HTTPError: Error, Equatable, Sendable {
    /// Transport-level failure (DNS, connection drop, TLS) — `description` carries the underlying message.
    case transport(String)
    /// HTTP status outside 2xx. Body retained so callers can decode error payloads.
    case status(code: Int, body: Data)
    /// Response body could not be decoded into the expected shape.
    case decoding(String)
    /// Request was cancelled mid-flight (e.g. task cancellation).
    case cancelled
}
