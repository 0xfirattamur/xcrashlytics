import Foundation

struct CommandFailure: Equatable {
    var code: String
    var exitCode: Int32
    var message: String
    var hint: String?
}
