import Foundation

struct IssueCriteria: Sendable {
    var query: String?
    var match: String?
    var type: String?
    var minEvents: Int?
    var appVersion: String?
    var sinceVersion: String?
    var file: String?
    var symbol: String?
    var domain: String?
    var userInfoKey: [String]
    var userId: String?

    var versions: VersionCriteria {
        VersionCriteria(appVersion: appVersion, sinceVersion: sinceVersion)
    }

    init(
        query: String? = nil, match: String? = nil, type: String? = nil,
        minEvents: Int? = nil, appVersion: String? = nil, sinceVersion: String? = nil,
        file: String? = nil, symbol: String? = nil, domain: String? = nil,
        userInfoKey: [String] = [], userId: String? = nil
    ) {
        self.query = query; self.match = match; self.type = type
        self.minEvents = minEvents; self.appVersion = appVersion; self.sinceVersion = sinceVersion
        self.file = file; self.symbol = symbol; self.domain = domain
        self.userInfoKey = userInfoKey; self.userId = userId
    }
}
