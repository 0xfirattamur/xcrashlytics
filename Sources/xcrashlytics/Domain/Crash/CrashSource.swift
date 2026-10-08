import Foundation

enum CrashSource: String, Sendable, Hashable, CaseIterable {
    case firebase
    case xcode
}
