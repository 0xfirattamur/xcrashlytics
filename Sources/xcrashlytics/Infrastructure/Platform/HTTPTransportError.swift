import Foundation

/// Errors raised by `HTTPClient` implementations. HTTP statuses are not
/// errors here: transports return every response and callers interpret it.
enum HTTPTransportError: Error, Equatable, Sendable {
    case transport(String)
    case cancelled
}
