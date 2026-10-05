//
//  IssueFilterTests.swift
//  xcrashlytics
//

import Testing
@testable import xcrashlytics

@Suite("issue filter")
struct IssueFilterTests {
    func makeIssue(
        id: String = "I1",
        type: String = "EXC_BAD_ACCESS",
        version: String? = "6.16.0",
        description: String? = "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
        eventsCount: Int? = 42
    ) -> CrashIssue {
        CrashIssue(providerId: id, title: description, exceptionType: type,
        eventsCount: eventsCount, lastSeenVersion: version)
    }

    @Test("matchesIssueFields applies type, minEvents, version, file, and symbol filters")
    func fieldFilters() {
        let issue = makeIssue()
        #expect(IssueFilter(criteria: .init(type: "exc_bad_access")).matchesIssueFields(issue))
        #expect(!IssueFilter(criteria: .init(type: "FATAL")).matchesIssueFields(issue))
        #expect(!IssueFilter(criteria: .init(minEvents: 100)).matchesIssueFields(issue))
        #expect(IssueFilter(criteria: .init(appVersion: "6.16.0")).matchesIssueFields(issue))
        #expect(IssueFilter(criteria: .init(file: "BlurDetectionService.swift")).matchesIssueFields(issue))
        #expect(IssueFilter(criteria: .init(symbol: "BlurDetectionService.classifyWithML(_:)")).matchesIssueFields(issue))
    }

    @Test("app-version matches either the first- or last-seen version")
    func appVersionMatchesSeenRange() {
        let issue = CrashIssue(providerId: "I1", exceptionType: "EXC_BAD_ACCESS",
        firstSeenVersion: "6.2.0", lastSeenVersion: "6.16.0")
        #expect(IssueFilter(criteria: .init(appVersion: "6.16.0")).matchesIssueFields(issue))
        #expect(IssueFilter(criteria: .init(appVersion: "6.2.0")).matchesIssueFields(issue))
        #expect(!IssueFilter(criteria: .init(appVersion: "6.10.0")).matchesIssueFields(issue))
    }

    @Test("since-version compares against the last-seen version")
    func sinceVersionUsesLastSeen() {
        let issue = CrashIssue(providerId: "I1", exceptionType: "EXC_BAD_ACCESS",
        firstSeenVersion: "6.2.0", lastSeenVersion: "6.16.0")
        #expect(IssueFilter(criteria: .init(sinceVersion: "6.10.0")).matchesIssueFields(issue))
        #expect(!IssueFilter(criteria: .init(sinceVersion: "6.17.0")).matchesIssueFields(issue))
    }

    @Test("query terms match the haystack case-insensitively")
    func queryMatch() {
        let issue = makeIssue()
        #expect(IssueFilter(criteria: .init(query: "BlurDetection")).matchesIssueFields(issue))
        #expect(!IssueFilter(criteria: .init(query: "checkout")).matchesIssueFields(issue))
    }

    @Test("reverse-DNS terms are event metadata queries")
    func metadataQueryDetection() {
        #expect(IssueFilter.isEventMetadataQuery("com.metrickit.diagnostics.cpu"))
        #expect(IssueFilter.isEventMetadataQuery("reason=cpu"))
        #expect(!IssueFilter.isEventMetadataQuery("checkout crash"))
    }

    @Test("hasSearchCriteria is false for bare listing")
    func bareCriteria() {
        #expect(!IssueFilter(criteria: .init()).hasSearchCriteria)
        #expect(IssueFilter(criteria: .init(query: "x")).hasSearchCriteria)
        #expect(IssueFilter(criteria: .init(userInfoKey: ["k=v"])).hasSearchCriteria)
    }

    @Test("search limit defaults widen only when criteria exist")
    func searchLimits() {
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: false, hasCriteria: false) == 20)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: false, hasCriteria: true) == 200)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: 500, all: false, hasCriteria: true) == 500)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: true, hasCriteria: true) == 2_000)
    }

    @Test("empty-result hint ladder: widen, then --all, then exhausted")
    func hintLadder() {
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 200, fetchLimit: 200, matchedCount: 0)
            == "0 matches in top 200 by impact. Rerun with --search-limit 1000.")
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 2_000, fetchLimit: 2_000, matchedCount: 0)
            == "0 matches in top 2000 by impact. Rerun with --all.")
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 50, fetchLimit: 200, matchedCount: 0)
            == "0 matches in all 50 fetched issues.")
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: false, fetchedCount: 200, fetchLimit: 200, matchedCount: 0) == nil)
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 200, fetchLimit: 200, matchedCount: 3) == nil)
    }

    // MARK: - matchesEventMetadata

    private func makeEvent(userId: String? = nil, rawJSON: String? = nil) -> FirebaseEvent {
        FirebaseEvent(eventId: "E1", userId: userId, rawJSON: rawJSON)
    }

    @Test("matchesEventMetadata: userId match vs mismatch")
    func eventMetadataUserIdFilter() {
        let issue = makeIssue()
        let event = makeEvent(userId: "user-abc")

        // exact match passes
        let matchFilter = IssueFilter(criteria: .init(userId: "user-abc"))
        #expect(matchFilter.matchesEventMetadata(issue: issue, event: event))

        // different userId fails
        let mismatchFilter = IssueFilter(criteria: .init(userId: "user-xyz"))
        #expect(!mismatchFilter.matchesEventMetadata(issue: issue, event: event))

        // no userId criterion always passes
        let noUserFilter = IssueFilter(criteria: .init())
        #expect(noUserFilter.matchesEventMetadata(issue: issue, event: event))
    }

    @Test("matchesEventMetadata: domain filter uses prefix matching via searchText")
    func eventMetadataDomainFilter() {
        let issue = makeIssue()
        let json = #"""
        {
          "eventId": "E1",
          "error": { "domain": "com.apple.CoreData.SQLite" }
        }
        """#
        let event = makeEvent(rawJSON: json)

        // matching domain prefix passes
        let matchFilter = IssueFilter(criteria: .init(domain: "com.apple.CoreData"))
        #expect(matchFilter.matchesEventMetadata(issue: issue, event: event))

        // non-matching domain fails
        let mismatchFilter = IssueFilter(criteria: .init(domain: "com.metrickit"))
        #expect(!mismatchFilter.matchesEventMetadata(issue: issue, event: event))
    }

    @Test("matchesEventMetadata: userInfoKey filter with key-only and key=value forms")
    func eventMetadataUserInfoKeyFilter() {
        let issue = makeIssue()
        let json = #"""
        {
          "eventId": "E1",
          "error": {
            "userInfo": {
              "reason": "memory pressure",
              "diagnosis": "oom"
            }
          }
        }
        """#
        let event = makeEvent(rawJSON: json)

        // key-only presence check passes
        let keyOnly = IssueFilter(criteria: .init(userInfoKey: ["reason"]))
        #expect(keyOnly.matchesEventMetadata(issue: issue, event: event))

        // key=value exact match passes
        let keyValue = IssueFilter(criteria: .init(userInfoKey: ["reason=memory pressure"]))
        #expect(keyValue.matchesEventMetadata(issue: issue, event: event))

        // wrong value fails
        let wrongValue = IssueFilter(criteria: .init(userInfoKey: ["reason=cpu spike"]))
        #expect(!wrongValue.matchesEventMetadata(issue: issue, event: event))

        // absent key fails
        let absentKey = IssueFilter(criteria: .init(userInfoKey: ["top_frames"]))
        #expect(!absentKey.matchesEventMetadata(issue: issue, event: event))
    }
}
