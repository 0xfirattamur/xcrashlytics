import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    func makeIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/events") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let body = #"""
            {
              "groups": [
                {
                  "issue": {
                    "id": "I1",
                    "title": "Crash in Checkout",
                    "subtitle": "SIGSEGV",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0",
                    "signals": [{ "signal": "SIGSEGV" }]
                  },
                  "metrics": [{ "eventsCount": "42", "impactedUsersCount": "12" }]
                }
              ]
            }
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeMultiIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/events") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                return FakeHTTPClient.response(
                    request.url!, status: 200,
                    body: TopVersionsFixture.body([("6.16.0", "937"), ("6.15.0", "900")]))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let body = #"""
            {
              "groups": [
                {
                  "issue": {
                    "id": "I1",
                    "title": "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
                    "subtitle": "SIGSEGV",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0",
                    "signals": [{ "signal": "SIGSEGV" }]
                  },
                  "metrics": [{ "eventsCount": "42", "impactedUsersCount": "12" }]
                },
                {
                  "issue": {
                    "id": "I2",
                    "title": "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
                    "subtitle": "SIGSEGV",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0",
                    "signals": [{ "signal": "SIGSEGV" }]
                  },
                  "metrics": [{ "eventsCount": "4", "impactedUsersCount": "2" }]
                },
                {
                  "issue": {
                    "id": "I3",
                    "title": "[Payments] CheckoutCoordinator.swift - CheckoutCoordinator.submit()",
                    "subtitle": "SIGABRT",
                    "errorType": "NON_FATAL",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "100", "impactedUsersCount": "50" }]
                }
              ]
            }
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeMultiIssuesWithEventsHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return try makeMultiIssuesHTTP().handler!(request)
            }
            #expect(url.path.hasSuffix("/events") == true)
            if url.query?.contains("filter.issue.id=I1") == true {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"events":[{"eventId":"E1","eventTime":"2026-06-07T20:00:00Z"}]}
                """#.utf8))
            }
            if url.query?.contains("filter.issue.id=I2") == true {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"events":[{"eventId":"E2","eventTime":"2026-06-01T20:00:00Z"}]}
                """#.utf8))
            }
            return FakeHTTPClient.response(url, status: 200, body: Data(#"{"events":[]}"#.utf8))
        }
    }

    func makeMetricKitHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                let body = #"""
                {
                  "groups": [
                    {
                      "issue": {
                        "id": "MX",
                        "title": "Background diagnostic",
                        "subtitle": "MetricKit payload",
                        "errorType": "NON_FATAL",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "5", "impactedUsersCount": "2" }]
                    },
                    {
                      "issue": {
                        "id": "OTHER",
                        "title": "Unrelated",
                        "subtitle": "No metadata",
                        "errorType": "NON_FATAL",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "4", "impactedUsersCount": "1" }]
                    }
                  ]
                }
                """#
                return FakeHTTPClient.response(url, status: 200, body: Data(body.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            if url.query?.contains("filter.issue.id=MX") == true {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {
                  "events": [
                    {
                      "eventId": "E-MX",
                      "eventTime": "2026-06-08T10:00:00Z",
                      "error": {
                        "domain": "com.metrickit.diagnostics.cpu",
                        "userInfo": {
                          "reason": "cpu spike",
                          "diagnosis": "main-thread hang",
                          "top_frames": "BlurDetectionService.analyzeBlur"
                        }
                      }
                    }
                  ]
                }
                """#.utf8))
            }
            return FakeHTTPClient.response(url, status: 200, body: Data(#"{"events":[]}"#.utf8))
        }
    }

    func makeUserIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {
                  "groups": [
                    {
                      "issue": {
                        "id": "I1",
                        "title": "[Core] UserCrash.swift - UserCrash.run()",
                        "errorType": "EXC_BAD_ACCESS",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "3", "impactedUsersCount": "2" }]
                    },
                    {
                      "issue": {
                        "id": "I2",
                        "title": "[Core] OtherCrash.swift - OtherCrash.run()",
                        "errorType": "EXC_BAD_ACCESS",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "4", "impactedUsersCount": "3" }]
                    }
                  ]
                }
                """#.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            // The user-id filter pass requests page_size=2; the later
            // last-seen sampling pass requests page_size=1.
            let pageSize = url.issuesQueryItem(named: "page_size")
            #expect(pageSize == "2" || pageSize == "1")
            if url.query?.contains("filter.issue.id=I1") == true {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {"events":[
                  {"eventId":"E-other","user":{"id":"other-user"}},
                  {"eventId":"E-target","user":{"id":"target-user"}}
                ]}
                """#.utf8))
            }
            return FakeHTTPClient.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E2","user":{"id":"other-user"}}]}
            """#.utf8))
        }
    }

    func makeRankedIssuesHTTP(
        matchIndex: Int?,
        total: Int,
        inspect: ((URLRequest) -> Void)? = nil
    ) -> FakeHTTPClient {
        FakeHTTPClient { request in
            inspect?(request)
            if request.url?.path.hasSuffix("/events") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let groups = (1...total).map { index in
                let title = index == matchIndex
                    ? "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)"
                    : "[Core] CheckoutCoordinator.swift - CheckoutCoordinator.submit()"
                return #"""
                {
                  "issue": {
                    "id": "I\#(index)",
                    "title": "\#(title)",
                    "subtitle": "SIGSEGV",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0",
                    "signals": [{ "signal": "SIGSEGV" }]
                  },
                  "metrics": [{ "eventsCount": "\#(100 - min(index, 99))", "impactedUsersCount": "1" }]
                }
                """#
            }.joined(separator: ",")
            let body = #"{"groups":[\#(groups)]}"#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeVersionedIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/events") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                return FakeHTTPClient.response(
                    request.url!, status: 200,
                    body: TopVersionsFixture.body([("6.17.0", "20"), ("6.16.0", "19"), ("6.15.0", "18")]))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let body = #"""
            {
              "groups": [
                {
                  "issue": {
                    "id": "OLD",
                    "title": "[Core] Old.swift - Old.run()",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "10", "impactedUsersCount": "2" }]
                },
                {
                  "issue": {
                    "id": "NEW",
                    "title": "[Core] New.swift - New.run()",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.17.0"
                  },
                  "metrics": [{ "eventsCount": "4", "impactedUsersCount": "1" }]
                }
              ]
            }
            """#
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    /// `--by-day`: topIssues answers with the whole-window total first, then one point per UTC
    /// day (a zero day and a repeated day included), as the real report does.
    func makeTrendHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            guard let url = request.url else {
                return FakeHTTPClient.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"""
                {
                  "groups": [
                    {
                      "issue": {
                        "id": "TREND",
                        "title": "[Core] Trend.swift - Trend.run()",
                        "errorType": "EXC_BAD_ACCESS",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [
                        {"eventsCount":"737","impactedUsersCount":"120",
                         "startTime":"2026-06-01T12:00:00Z","endTime":"2026-06-08T12:00:00Z"},
                        {"eventsCount":"700","startTime":"2026-06-01T12:00:00Z","endTime":"2026-06-02T00:00:00Z"},
                        {"eventsCount":"0","startTime":"2026-06-02T00:00:00Z","endTime":"2026-06-03T00:00:00Z"},
                        {"eventsCount":"35","startTime":"2026-06-07T00:00:00Z","endTime":"2026-06-08T00:00:00Z"},
                        {"eventsCount":"35","startTime":"2026-06-07T00:00:00Z","endTime":"2026-06-08T00:00:00Z"},
                        {"eventsCount":"2","startTime":"2026-06-08T00:00:00Z","endTime":"2026-06-08T12:00:00Z"}
                      ]
                    }
                  ]
                }
                """#.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            return FakeHTTPClient.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E3","eventTime":"2026-06-08T08:00:00Z"}]}
            """#.utf8))
        }
    }
}

extension URL {
    func issuesQueryItem(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
