//
//  GroupsCommandTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore
import XCrashlyticsTestSupport
@testable import xcrashlytics

@Suite("xcrashlytics groups")
struct GroupsCommandTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("groups related live Firebase issues")
    func groupsFirebaseIssues() async throws {
        let fs = try makeConfig()
        let http = makeIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try GroupsCommand.parse([])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        #expect(output.contains("blurdetectionservice.classifywithml(_:)"))
        #expect(output.contains("firebase: 2 issues"))
        #expect(output.contains("FB-I1, FB-I2"))
        #expect(output.contains("50 events / 15 users"))
    }

    @Test("renders grouped Firebase issues as JSON")
    func rendersJSON() async throws {
        let fs = try makeConfig()
        let http = makeIssuesHTTP()
        let ctx = CommandContext(
            fileSystem: fs,
            processRunner: MockProcessRunner(),
            clock: FixedClock()
        )
        let cmd = try GroupsCommand.parse(["--format", "json"])

        let output = try await cmd.runWithContext(
            ctx.withFirebaseHTTP(http)

        )

        let env = try Envelope(output)
        let groups = try #require(env.data["groups"]?.array)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group["symbol"]?.string == "blurdetectionservice.classifywithml(_:)")
        #expect(group["totalEvents"]?.int == 50)
        #expect(group["crossSource"]?.bool == false)
        #expect(group["firebase"]?.array?.compactMap { $0["id"]?.string } == ["FB-I1", "FB-I2"])
    }

    private func makeConfig() throws -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        try ConfigFile(fileSystem: fs).save(Config(appId: appId))
        return fs
    }

    private func makeIssuesHTTP() -> MockHTTPClient {
        MockHTTPClient { request in
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            let body = #"""
            {
              "groups": [
                {
                  "issue": {
                    "id": "I1",
                    "title": "[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "42", "impactedUsersCount": "12" }]
                },
                {
                  "issue": {
                    "id": "I2",
                    "title": "[Core] Blur.swift - BlurDetectionService.classifyWithML(_:)",
                    "errorType": "EXC_BAD_ACCESS",
                    "lastSeenVersion": "6.16.0"
                  },
                  "metrics": [{ "eventsCount": "8", "impactedUsersCount": "3" }]
                }
              ]
            }
            """#
            return MockHTTPClient.response(request.url!, status: 200, body: Data(body.utf8))
        }
    }
}
