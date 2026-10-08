import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics issues agent ergonomics")
struct IssuesAgentErgonomicsTests {
    private let appId = "1:1234567890:ios:abcdef"

    @Test("--since-version restricts the topIssues report to the window's versions at or above it")
    func filtersIssuesBySinceVersion() async throws {
        let fileStore = try makeConfig()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: FixedDateProvider()
        )
        let cmd = try IssuesCommand.parse([
            "--since-version", "6.16.0",
            "--format", "json",
            "--limit", "10"
        ])
        let httpClient = makeVersionedIssuesHTTP()

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        let topIssues = try #require(httpClient.requests.first { $0.url?.path.hasSuffix("/reports/topIssues") == true })
        #expect(TopVersionsFixture.displayNames(of: topIssues) == ["6.16.0 (19)", "6.17.0 (20)"])
        // The server did the filtering: the client does not re-filter on the chronological last-seen version.
        let env = try Envelope(output)
        let ids = env.data["issues"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(ids == ["FB-I1", "FB-I2", "FB-I3"])
        let matched = env.data["matchedVersions"]?.array?.compactMap(\.string)
        #expect(matched == ["6.17.0 (20)", "6.16.0 (19)"])
    }

    private func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    private func makeVersionedIssuesHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            if request.url?.path.hasSuffix("/events") == true {
                return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"{"events":[]}"#.utf8))
            }
            if request.url?.path.hasSuffix("/reports/topVersions") == true {
                return FakeHTTPClient.response(
                    request.url!, status: 200,
                    body: TopVersionsFixture.body([("6.17.0", "20"), ("6.16.0", "19"), ("6.15.9", "18")]))
            }
            #expect(request.url?.path.hasSuffix("/reports/topIssues") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
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
}
