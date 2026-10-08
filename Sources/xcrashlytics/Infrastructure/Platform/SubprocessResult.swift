import Foundation

struct SubprocessResult: Sendable, Equatable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
}
