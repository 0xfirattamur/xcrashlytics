import Foundation

struct XcodeIssueSummary: Encodable, Sendable {
    var id: String
    var source: String
    var exceptionType: String
    var appVersion: String?
    var deviceModel: String?
    var topAppSymbol: String?

    init(_ crash: XcodeCrash) {
        self.id = crash.event.id
        self.source = crash.event.source.rawValue
        self.exceptionType = crash.event.exception.exceptionType
        self.appVersion = crash.event.bundleVersion
        self.deviceModel = crash.event.deviceModel
        self.topAppSymbol = crash.event.frames.first?.symbol
    }
}
