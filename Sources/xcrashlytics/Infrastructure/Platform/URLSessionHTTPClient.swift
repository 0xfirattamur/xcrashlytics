import Foundation

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPTransportError.transport("the server did not answer with an HTTP response.")
            }
            return (data, httpResponse)
        } catch let error as HTTPTransportError {
            throw error
        } catch is CancellationError {
            throw HTTPTransportError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw HTTPTransportError.cancelled
        } catch {
            throw HTTPTransportError.transport(error.localizedDescription)
        }
    }
}
