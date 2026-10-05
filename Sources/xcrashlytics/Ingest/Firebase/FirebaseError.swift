//
//  FirebaseError.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Errors raised by `CrashlyticsClient`.
enum FirebaseError: Error, Equatable, Sendable {
    /// No stored credentials; the user must run `firebase login`.
    case notAuthenticated
    /// Token refresh failed (after a 401).
    case refreshFailed(String)
    /// API returned a non-success status that wasn't retryable.
    case apiError(code: Int, message: String)
    /// Rate-limited and exhausted retries.
    case rateLimited(retries: Int)
    /// Response body could not be decoded.
    case decodingFailed(String)
    /// Request could not be built from the given input (bad id, malformed URL).
    case invalidRequest(String)
}
