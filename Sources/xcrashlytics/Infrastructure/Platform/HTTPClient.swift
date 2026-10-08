import Foundation

protocol HTTPClient: Sendable {
    /// Throws `HTTPTransportError` for transport failures or cancellation.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
