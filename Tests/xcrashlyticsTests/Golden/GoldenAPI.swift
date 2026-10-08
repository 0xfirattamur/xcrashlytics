import Foundation
@testable import xcrashlytics

/// Serves the synthetic Crashlytics API (and the Google token endpoint), routed by URL path and query.
///
/// Special issue ids trigger failures: `I404` (404), `I403` (403), `I401` (401 even after a refresh),
/// `I429` (429 with `Retry-After: 0`, so retries cost no time), `I500` (500, same), `IBAD` (undecodable body),
/// `INET` (transport failure).
enum GoldenAPI {
    static func respond(to request: URLRequest, in world: GoldenWorld) throws -> (Data, HTTPURLResponse) {
        let url = try require(request.url)
        if url == FirebaseToolsTokenProvider.tokenEndpoint { return token(url, world.login) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let issueFilter = value("filter.issue.id")
        let path = url.path

        if path.contains("/issues/") {
            return try issueDetail(url, id: String(path.split(separator: "/").last ?? ""))
        }
        if path.hasSuffix("/events") {
            return try events(url, issueId: issueFilter ?? "", pageSize: value("page_size").flatMap(Int.init), world: world)
        }
        if let failure = try failure(for: issueFilter, url: url) { return failure }
        if let name = world.failingReports.first(where: { path.hasSuffix("/reports/\($0)") }) {
            return reply(url, status: 500, body: #"{"error":{"message":"\#(name) failed"}}"#, headers: ["Retry-After": "0"])
        }
        return report(url, items: items, issueFilter: issueFilter, world: world)
    }

    private static func report(_ url: URL, items: [URLQueryItem], issueFilter: String?, world: GoldenWorld) -> (Data, HTTPURLResponse) {
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let versionNames = items.filter { $0.name == "filter.version.displayNames" }.compactMap(\.value)
        let daily = value("granularity") == "TIME_GRANULARITY_DAY"
        let path = url.path
        switch true {
        case path.hasSuffix("/reports/topIssues"):
            var body = GoldenReports.topIssues(versionNames: versionNames, daily: daily)
            if world.endlessIssuePages {
                let page = value("page_token").flatMap { Int($0.dropFirst()) } ?? 1
                body["nextPageToken"] = "p\(page + 1)"
            }
            return ok(url, body)
        case path.hasSuffix("/reports/topVersions"):
            return ok(url, GoldenReports.topVersions(issueId: issueFilter, daily: daily))
        case path.hasSuffix("/reports/topOperatingSystems"):
            return ok(url, GoldenReports.topOperatingSystems(issueId: issueFilter))
        case path.hasSuffix("/reports/topAppleDevices"):
            return ok(url, GoldenReports.topAppleDevices(issueId: issueFilter))
        default:
            return reply(url, status: 404, body: #"{"error":{"message":"no such route \#(path)"}}"#)
        }
    }

    // MARK: - Routes

    private static func issueDetail(_ url: URL, id: String) throws -> (Data, HTTPURLResponse) {
        if let failure = try failure(for: id, url: url) { return failure }
        guard let issue = (GoldenReports.issues + [GoldenReports.unrankedIssue]).first(where: { $0.id == id }) else {
            return reply(url, status: 404, body: #"{"error":{"message":"issue not found"}}"#)
        }
        return ok(url, GoldenReports.issueObject(issue))
    }

    private static func events(_ url: URL, issueId: String, pageSize: Int?, world: GoldenWorld) throws -> (Data, HTTPURLResponse) {
        if world.failingEventIssues.contains(issueId) {
            return reply(url, status: 500, body: #"{"error":{"message":"events unavailable"}}"#, headers: ["Retry-After": "0"])
        }
        if let failure = try failure(for: issueId, url: url) { return failure }
        let bodies: [String]
        switch issueId {
        case "I1": bodies = [GoldenEvents.fatalWithEverything, GoldenEvents.olderFatal]
        case "I2": bodies = [GoldenEvents.nonFatal]
        case "I3": bodies = [GoldenEvents.noCrashedThread]
        case "I4": bodies = [GoldenEvents.simpleFatal(id: "E5", time: "2026-06-13T11:00:00Z", symbol: "objectdestroyTm", file: "KeyboardCore.swift")]
        case "I5": bodies = [GoldenEvents.simpleFatal(id: "E6", time: "2026-06-10T11:00:00Z", symbol: "BlurService.classify(_:)", file: "BlurService.swift")]
        case "IMANY": bodies = (1...60).map { GoldenEvents.simpleFatal(id: "M\($0)", time: "2026-06-13T11:00:00Z", symbol: "many()", file: "Many.swift") }
        default: bodies = []
        }
        let page = pageSize.map { Array(bodies.prefix($0)) } ?? bodies
        return reply(url, status: 200, body: #"{"events":[\#(page.joined(separator: ","))]}"#)
    }

    /// The error response a special issue id asks for, if any.
    private static func failure(for issueId: String?, url: URL) throws -> (Data, HTTPURLResponse)? {
        switch issueId {
        case "I404": return reply(url, status: 404, body: "{}")
        case "I403": return reply(url, status: 403, body: #"{"error":{"message":"Caller lacks permission"}}"#)
        case "I401": return reply(url, status: 401, body: #"{"error":{"message":"Invalid Credentials"}}"#)
        case "I429": return reply(url, status: 429, body: "{}", headers: ["Retry-After": "0"])
        case "I500": return reply(url, status: 500, body: #"{"error":{"message":"Internal error encountered."}}"#, headers: ["Retry-After": "0"])
        case "IBAD": return reply(url, status: 200, body: "[1, 2]")
        case "INET": throw HTTPTransportError.transport("The Internet connection appears to be offline.")
        default: return nil
        }
    }

    private static func token(_ url: URL, _ login: GoldenWorld.Login) -> (Data, HTTPURLResponse) {
        switch login {
        case .revoked:
            return reply(url, status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)
        case .tokenServiceDown:
            return reply(url, status: 500, body: #"{"error":"backend_error"}"#)
        case .ok, .missing:
            return reply(url, status: 200, body: #"{"access_token":"golden-access-token","expires_in":3600}"#)
        }
    }

    // MARK: - Responses

    private static func ok(_ url: URL, _ object: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return FakeHTTPClient.response(url, status: 200, body: data)
    }

    private static func reply(_ url: URL, status: Int, body: String, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        FakeHTTPClient.response(url, status: status, body: Data(body.utf8), headers: headers)
    }

    private static func require(_ url: URL?) throws -> URL {
        guard let url else { throw HTTPTransportError.transport("request without a URL") }
        return url
    }
}
