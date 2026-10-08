import Foundation

/// A filesystem write that failed, described without the temp-file name.
struct FileStoreError: Error, LocalizedError, Equatable {
    var path: String
    var reason: String

    var errorDescription: String? { "could not write \(path): \(reason)" }

    init(path: String, underlying error: Error) {
        let nsError = error as NSError
        self.path = path
        self.reason = nsError.localizedFailureReason ?? nsError.localizedDescription
    }
}
