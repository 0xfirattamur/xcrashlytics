import Foundation

/// Honors `$HOME` so tests, CI, and sandboxes can redirect the Firebase login and Organizer paths.
enum HomeDirectoryLocator {
    static var path: String {
        ProcessInfo.processInfo.environment["HOME"]?.trimmedNonEmpty ?? NSHomeDirectory()
    }
}
