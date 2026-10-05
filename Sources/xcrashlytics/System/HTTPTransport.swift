//
//  HTTPClient.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Abstraction over `URLSession` so tests can swap in `MockHTTPTransport`.
protocol HTTPTransport: Sendable {
    /// Sends a request and returns the raw response body plus the typed HTTP response.
    /// - Throws: `HTTPError` for transport failures or cancellation.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production `HTTPTransport` backed by `URLSession`.
struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("non-HTTP response: \(type(of: response))")
            }
            return (data, http)
        } catch let error as HTTPError {
            throw error
        } catch is CancellationError {
            throw HTTPError.cancelled
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
    }
}
