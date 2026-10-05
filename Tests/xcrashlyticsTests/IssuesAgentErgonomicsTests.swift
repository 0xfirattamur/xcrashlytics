//
//  IssuesAgentErgonomicsTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics issues agent ergonomics")
struct IssuesAgentErgonomicsTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("filters issues by minimum app version")
    func filtersIssuesBySinceVersion() async throws {
        let fs = try makeConfig()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse([
            "--since-version", "6.16.0",
            "--format", "json",
            "--limit", "10"
        ])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(makeVersionedIssuesHTTP())

        )

        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids.contains("FB-I2"))
        #expect(ids.contains("FB-I3"))
        #expect(!ids.contains("FB-I1"))
    }

    @Test("agent JSON includes compact related group hints by default")
    func showsRelatedGroupHintsByDefault() async throws {
        let fs = try makeConfig()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try IssuesCommand.parse(["blur", "--format", "json", "--limit", "200"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(makeRelatedIssuesHTTP())

        )

        let env = try Envelope(output)
        let group = try #require(env.data["relatedGroups"]?[0])
        let groupIds = group["issueIds"]?.array?.compactMap(\.string) ?? []
        #expect(groupIds.contains("FB-I1"))
        #expect(groupIds.contains("FB-I2"))
    }

    private func makeConfig() throws -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        return fs
    }

    private func makeVersionedIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"""
            {"groups":[
              {
                "issue":{
                  "id":"I1",
                  "title":"[Core] Old.swift - Old.run()",
                  "errorType":"EXC_BAD_ACCESS",
                  "lastSeenVersion":"6.15.9"
                },
                "metrics":[{"eventsCount":"5","impactedUsersCount":"1"}]
              },
              {
                "issue":{
                  "id":"I2",
                  "title":"[Core] Current.swift - Current.run()",
                  "errorType":"EXC_BAD_ACCESS",
                  "lastSeenVersion":"6.16.0"
                },
                "metrics":[{"eventsCount":"4","impactedUsersCount":"1"}]
              },
              {
                "issue":{
                  "id":"I3",
                  "title":"[Core] New.swift - New.run()",
                  "errorType":"EXC_BAD_ACCESS",
                  "lastSeenVersion":"6.17.0"
                },
                "metrics":[{"eventsCount":"3","impactedUsersCount":"1"}]
              }
            ]}
            """#.utf8))
        }
    }

    private func makeRelatedIssuesHTTP() -> MockHTTPTransport {
        MockHTTPTransport { request in
            if request.url?.path.hasSuffix("/events") == true {
                return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            return MockHTTPTransport.response(request.url!, status: 200, body: Data(#"""
            {"groups":[
              {
                "issue":{
                  "id":"I1",
                  "title":"[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
                  "subtitle":"SIGSEGV",
                  "errorType":"EXC_BAD_ACCESS",
                  "lastSeenVersion":"6.16.0",
                  "signals":[{"signal":"SIGSEGV"}]
                },
                "metrics":[{"eventsCount":"42","impactedUsersCount":"12"}]
              },
              {
                "issue":{
                  "id":"I2",
                  "title":"[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
                  "subtitle":"SIGSEGV",
                  "errorType":"EXC_BAD_ACCESS",
                  "lastSeenVersion":"6.16.0",
                  "signals":[{"signal":"SIGSEGV"}]
                },
                "metrics":[{"eventsCount":"4","impactedUsersCount":"2"}]
              },
              {
                "issue":{
                  "id":"I3",
                  "title":"[Payments] CheckoutCoordinator.swift - CheckoutCoordinator.submit()",
                  "subtitle":"SIGABRT",
                  "errorType":"NON_FATAL",
                  "lastSeenVersion":"6.16.0"
                },
                "metrics":[{"eventsCount":"100","impactedUsersCount":"50"}]
              }
            ]}
            """#.utf8))
        }
    }
}
