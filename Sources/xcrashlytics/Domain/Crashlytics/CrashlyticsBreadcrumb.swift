import Foundation

struct CrashlyticsBreadcrumb: Sendable, Equatable {
    var time: String?
    var title: String?
    var params: [String: String]
}
