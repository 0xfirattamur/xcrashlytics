import Foundation
import Testing
@testable import xcrashlytics

extension IssuesCommandTests {
    func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    func makeConfig() throws -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        return fs
    }

    func makeIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
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
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeMultiIssuesHTTPConfig() throws -> InMemoryFileSystem {
        try makeConfig()
    }

    func makeMultiIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
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
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeMultiIssuesWithEventsHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            guard let url = request.url else {
                return MockHTTPTransport.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return try makeMultiIssuesHTTP().handler!(request)
            }
            #expect(url.path.hasSuffix("/events") == true)
            if url.query?.contains("filter.issue.id=I1") == true {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
                {"events":[{"eventId":"E1","eventTime":"2026-06-07T20:00:00Z"}]}
                """#.utf8))
            }
            if url.query?.contains("filter.issue.id=I2") == true {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
                {"events":[{"eventId":"E2","eventTime":"2026-06-01T20:00:00Z"}]}
                """#.utf8))
            }
            return MockHTTPTransport.response(url, status: 200, body: Data(#"{"events":[]}"#.utf8))
        }
    }

    func makeMetricKitHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            guard let url = request.url else {
                return MockHTTPTransport.response(URL(string: "https://example.com")!, status: 500, body: Data())
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
                return MockHTTPTransport.response(url, status: 200, body: Data(body.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            if url.query?.contains("filter.issue.id=MX") == true {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
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
            return MockHTTPTransport.response(url, status: 200, body: Data(#"{"events":[]}"#.utf8))
        }
    }

    func makeUserIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            guard let url = request.url else {
                return MockHTTPTransport.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
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
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
                {"events":[
                  {"eventId":"E-other","user":{"id":"other-user"}},
                  {"eventId":"E-target","user":{"id":"target-user"}}
                ]}
                """#.utf8))
            }
            return MockHTTPTransport.response(url, status: 200, body: Data(#"""
            {"events":[{"eventId":"E2","user":{"id":"other-user"}}]}
            """#.utf8))
        }
    }

    func makeRankedIssuesHTTP(
        matchIndex: Int?,
        total: Int,
        inspect: ((URLRequest) -> Void)? = nil
    ) -> MockHTTPTransport {
        MockHTTPTransport { request in
            inspect?(request)
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
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
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeVersionedIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
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
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }

    func makeTruncatedTrendHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            guard let url = request.url else {
                return MockHTTPTransport.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
                {
                  "groups": [
                    {
                      "issue": {
                        "id": "TREND",
                        "title": "[Core] Trend.swift - Trend.run()",
                        "errorType": "EXC_BAD_ACCESS",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "737", "impactedUsersCount": "120" }]
                    }
                  ]
                }
                """#.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            return MockHTTPTransport.response(url, status: 200, body: Data(#"""
            {
              "events": [
                {"eventId":"E1","eventTime":"2026-06-07T10:00:00Z"},
                {"eventId":"E2","eventTime":"2026-06-07T11:00:00Z"},
                {"eventId":"E3","eventTime":"2026-06-08T08:00:00Z"}
              ]
            }
            """#.utf8))
        }
    }

    func makeTrendHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            guard let url = request.url else {
                return MockHTTPTransport.response(URL(string: "https://example.com")!, status: 500, body: Data())
            }
            if url.path.hasSuffix("/reports/topIssues") {
                return MockHTTPTransport.response(url, status: 200, body: Data(#"""
                {
                  "groups": [
                    {
                      "issue": {
                        "id": "TREND",
                        "title": "[Core] Trend.swift - Trend.run()",
                        "errorType": "EXC_BAD_ACCESS",
                        "lastSeenVersion": "6.17.0"
                      },
                      "metrics": [{ "eventsCount": "3", "impactedUsersCount": "2" }]
                    }
                  ]
                }
                """#.utf8))
            }
            #expect(url.path.hasSuffix("/events") == true)
            return MockHTTPTransport.response(url, status: 200, body: Data(#"""
            {
              "events": [
                {"eventId":"E1","eventTime":"2026-06-07T10:00:00Z"},
                {"eventId":"E2","eventTime":"2026-06-07T11:00:00Z"},
                {"eventId":"E3","eventTime":"2026-06-08T08:00:00Z"}
              ]
            }
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
