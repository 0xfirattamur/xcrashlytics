import Foundation
@testable import xcrashlytics

/// Canned `reports/topVersions` bodies for command tests.
enum TopVersionsFixture {
    /// One group per `(displayVersion, buildVersion)`, in the given order.
    static func body(_ versions: [(String, String)], nextPageToken: String? = nil) -> Data {
        let groups = versions.map { display, build in
            #"{"version":{"displayVersion":"\#(display)","buildVersion":"\#(build)","displayName":"\#(display) (\#(build))"},"metrics":[{"eventsCount":"1"}]}"#
        }.joined(separator: ",")
        let token = nextPageToken.map { #","nextPageToken":"\#($0)""# } ?? ""
        return Data(#"{"groups":[\#(groups)]\#(token)}"#.utf8)
    }

    /// The repeated `filter.version.displayNames` values of a request, in query order.
    static func displayNames(of request: URLRequest) -> [String] {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [] }
        return items.filter { $0.name == "filter.version.displayNames" }.compactMap(\.value)
    }
}
