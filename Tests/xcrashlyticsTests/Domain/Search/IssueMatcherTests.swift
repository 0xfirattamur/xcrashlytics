import Testing
@testable import xcrashlytics

@Suite("issue filter")
struct IssueMatcherTests {
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
        #expect(IssueMatcher(criteria: .init(type: "exc_bad_access")).matchesIssueFields(issue))
        #expect(!IssueMatcher(criteria: .init(type: "FATAL")).matchesIssueFields(issue))
        #expect(!IssueMatcher(criteria: .init(minEvents: 100)).matchesIssueFields(issue))
        #expect(IssueMatcher(criteria: .init(file: "BlurDetectionService.swift")).matchesIssueFields(issue))
        #expect(IssueMatcher(criteria: .init(symbol: "BlurDetectionService.classifyWithML(_:)")).matchesIssueFields(issue))
    }

    @Test("query terms match the haystack case-insensitively")
    func queryMatch() {
        let issue = makeIssue()
        #expect(IssueMatcher(criteria: .init(query: "BlurDetection")).matchesIssueFields(issue))
        #expect(!IssueMatcher(criteria: .init(query: "checkout")).matchesIssueFields(issue))
    }

    @Test("reverse-DNS terms are event metadata queries")
    func metadataQueryDetection() {
        #expect(IssueMatcher.isEventMetadataQuery("com.metrickit.diagnostics.cpu"))
        #expect(IssueMatcher.isEventMetadataQuery("reason=cpu"))
        #expect(!IssueMatcher.isEventMetadataQuery("checkout crash"))
    }

    @Test("hasSearchCriteria is false for bare listing")
    func bareCriteria() {
        #expect(!IssueMatcher(criteria: .init()).hasSearchCriteria)
        #expect(IssueMatcher(criteria: .init(query: "x")).hasSearchCriteria)
        #expect(IssueMatcher(criteria: .init(userInfoKey: ["k=v"])).hasSearchCriteria)
    }

    @Test("search limit defaults widen only when criteria exist")
    func searchLimits() {
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: false, hasCriteria: false) == 20)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: false, hasCriteria: true) == 200)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: 500, all: false, hasCriteria: true) == 500)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: true, hasCriteria: true) == 2_000)
    }

    @Test("empty-result hint ladder: widen, then the cap, then exhausted")
    func hintLadder() {
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 200, fetchLimit: 200, matchedCount: 0)
            == "0 matches in top 200 by impact. Rerun with --search-limit 1000.")
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 2_000, fetchLimit: 2_000, matchedCount: 0)
            == "0 matches in the top 2000 issues by impact, the largest search window; no wider scan is possible. Narrow the filters or change --since.")
        #expect(!(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 2_000, fetchLimit: 2_000, matchedCount: 0) ?? "")
            .contains("--all"))
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 50, fetchLimit: 200, matchedCount: 0)
            == "0 matches in all 50 fetched issues.")
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: false, fetchedCount: 200, fetchLimit: 200, matchedCount: 0) == nil)
        #expect(IssueSearchPlanner.emptyResultHint(hasCriteria: true, fetchedCount: 200, fetchLimit: 200, matchedCount: 3) == nil)
    }

    // MARK: - matchesEventMetadata

    private func makeEvent(userId: String? = nil, rawJSON: String? = nil) -> CrashlyticsEvent {
        CrashlyticsEvent(eventId: "E1", userId: userId, rawJSON: rawJSON)
    }

    @Test("matchesEventMetadata: userId match vs mismatch")
    func eventMetadataUserIdFilter() {
        let issue = makeIssue()
        let event = makeEvent(userId: "user-abc")

        let matchFilter = IssueMatcher(criteria: .init(userId: "user-abc"))
        #expect(matchFilter.matchesEventMetadata(issue: issue, event: event))

        let mismatchFilter = IssueMatcher(criteria: .init(userId: "user-xyz"))
        #expect(!mismatchFilter.matchesEventMetadata(issue: issue, event: event))

        let noUserFilter = IssueMatcher(criteria: .init())
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

        let matchFilter = IssueMatcher(criteria: .init(domain: "com.apple.CoreData"))
        #expect(matchFilter.matchesEventMetadata(issue: issue, event: event))

        let mismatchFilter = IssueMatcher(criteria: .init(domain: "com.metrickit"))
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

        let keyOnly = IssueMatcher(criteria: .init(userInfoKey: ["reason"]))
        #expect(keyOnly.matchesEventMetadata(issue: issue, event: event))

        let keyValue = IssueMatcher(criteria: .init(userInfoKey: ["reason=memory pressure"]))
        #expect(keyValue.matchesEventMetadata(issue: issue, event: event))

        let wrongValue = IssueMatcher(criteria: .init(userInfoKey: ["reason=cpu spike"]))
        #expect(!wrongValue.matchesEventMetadata(issue: issue, event: event))

        let absentKey = IssueMatcher(criteria: .init(userInfoKey: ["top_frames"]))
        #expect(!absentKey.matchesEventMetadata(issue: issue, event: event))
    }

    // MARK: - Event-metadata deferral, type, versions, Xcode

    @Test("a code-looking term the issue text already matches needs no event sampling")
    func dottedTermMatchedByIssueText() {
        let issue = makeIssue()
        let filter = IssueMatcher(criteria: .init(query: "BlurDetectionService.swift"))
        #expect(filter.matchesIssueFields(issue))
        #expect(filter.unresolvedEventTerms(for: issue).isEmpty)
        #expect(!filter.requiresEventMetadata(for: issue))
    }

    @Test("a code-looking term the issue text misses is deferred to events, other terms are not")
    func dottedTermDeferred() {
        let issue = makeIssue()
        let filter = IssueMatcher(criteria: .init(query: "com.metrickit.cpu"))
        #expect(filter.matchesIssueFields(issue))
        #expect(filter.unresolvedEventTerms(for: issue) == ["com.metrickit.cpu"])
        #expect(filter.requiresEventMetadata(for: issue))
        #expect(!IssueMatcher(criteria: .init(query: "checkout")).matchesIssueFields(issue))
    }

    @Test("user, domain and userInfo filters always need events")
    func eventOnlyFilters() {
        let issue = makeIssue()
        #expect(IssueMatcher(criteria: .init(userId: "u")).requiresEventMetadata(for: issue))
        #expect(IssueMatcher(criteria: .init(domain: "d")).requiresEventMetadata(for: issue))
        #expect(IssueMatcher(criteria: .init(userInfoKey: ["k"])).requiresEventMetadata(for: issue))
        #expect(!IssueMatcher(criteria: .init(query: "blur")).requiresEventMetadata(for: issue))
    }

    @Test("--type matches Firebase's errorType or the exception type, case-insensitively")
    func typeMatchesErrorType() {
        let issue = CrashIssue(
            providerId: "I1", title: "t", exceptionType: "EXC_BAD_ACCESS", errorType: "FATAL")
        #expect(IssueMatcher(criteria: .init(type: "fatal")).matchesIssueFields(issue))
        #expect(IssueMatcher(criteria: .init(type: "exc_bad_access")).matchesIssueFields(issue))
        #expect(!IssueMatcher(criteria: .init(type: "NON_FATAL")).matchesIssueFields(issue))
        #expect(!IssueMatcher(criteria: .init(type: "ANR")).matchesIssueFields(issue))
    }

    @Test("--min-events counts as search criteria so the search window widens")
    func minEventsIsCriteria() {
        #expect(IssueMatcher(criteria: .init(minEvents: 100)).hasSearchCriteria)
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: nil, all: false, hasCriteria: true) == 200)
    }

    @Test("explicit --search-limit is capped at 2000")
    func searchLimitCap() {
        #expect(IssueSearchPlanner.resolvedSearchLimit(outputLimit: 20, explicit: 9_999, all: false, hasCriteria: true) == 2_000)
    }

    private func reported(_ display: String, _ build: String?) -> ReportedVersion {
        ReportedVersion(
            displayVersion: display, buildVersion: build, displayName: build.map { "\(display) (\($0))" } ?? display)
    }

    private var window: [ReportedVersion] {
        [reported("6.23.0", "1112"), reported("6.22.0", "1090"), reported("6.22.0", "1095"),
         reported("6.16.0", "937"), reported("5.3.1", "40"), reported("6.0.0-beta.1", "7")]
    }

    @Test("--app-version selects every build of that display version")
    func appVersionSelectsAllBuilds() {
        let names = IssueMatcher(criteria: .init(appVersion: "6.22.0")).selectVersions(from: window).map(\.displayName)
        #expect(names == ["6.22.0 (1090)", "6.22.0 (1095)"])
    }

    @Test("--app-version with a build selects only that build")
    func appVersionWithBuildSelectsOneBuild() {
        let names = IssueMatcher(criteria: .init(appVersion: "6.22.0 (1095)")).selectVersions(from: window).map(\.displayName)
        #expect(names == ["6.22.0 (1095)"])
        #expect(IssueMatcher(criteria: .init(appVersion: "6.22.0 (1)")).selectVersions(from: window).isEmpty)
    }

    @Test("--since-version selects versions at or above it, pre-releases below their release")
    func sinceVersionSelectsAtLeast() {
        let names = IssueMatcher(criteria: .init(sinceVersion: "6.16.0")).selectVersions(from: window).map(\.displayName)
        #expect(names == ["6.23.0 (1112)", "6.22.0 (1090)", "6.22.0 (1095)", "6.16.0 (937)"])
        let release = IssueMatcher(criteria: .init(sinceVersion: "6.0.0")).selectVersions(from: window).map(\.displayName)
        #expect(!release.contains("6.0.0-beta.1 (7)"))
    }

    @Test("both version flags must hold; no matching version selects nothing")
    func bothFlagsIntersect() {
        let both = IssueMatcher(criteria: .init(appVersion: "6.16.0", sinceVersion: "6.20.0"))
        #expect(both.selectVersions(from: window).isEmpty)
        #expect(IssueMatcher(criteria: .init(appVersion: "9.9.9")).selectVersions(from: window).isEmpty)
    }

    @Test("the same display name is selected once")
    func selectionDeduplicates() {
        let twice = window + [reported("6.23.0", "1112")]
        let names = IssueMatcher(criteria: .init(sinceVersion: "6.23.0")).selectVersions(from: twice).map(\.displayName)
        #expect(names == ["6.23.0 (1112)"])
    }

    @Test("version flags no longer filter Firebase issues by their chronological first/last version")
    func versionFlagsLeaveIssueFieldsAlone() {
        let inverted = CrashIssue(
            providerId: "I1", exceptionType: "FATAL", firstSeenVersion: "6.22.0", lastSeenVersion: "5.3.1")
        #expect(IssueMatcher(criteria: .init(appVersion: "6.22.0")).matchesIssueFields(inverted))
        #expect(IssueMatcher(criteria: .init(sinceVersion: "6.0.0")).matchesIssueFields(inverted))
        #expect(IssueMatcher(criteria: .init(appVersion: "6.22.0")).hasVersionFilter)
        #expect(!IssueMatcher(criteria: .init()).hasVersionFilter)
    }

    private func xcodeEvent(version: String? = "6.16.0", type: String = "EXC_BAD_ACCESS") -> CrashEvent {
        CrashEvent(
            id: "XC-1", source: .xcode, bundleVersion: version, crashedThreadIndex: 0,
            exception: ExceptionDescriptor(exceptionType: type),
            frames: [StackFrame(index: 0, binaryName: "App", symbol: "Checkout.pay()", file: "Checkout.swift")])
    }

    @Test("Xcode crashes share type, version, file, symbol, and min-events filters")
    func xcodeSharedFilters() {
        let event = xcodeEvent()
        #expect(IssueMatcher(criteria: .init(type: "exc_bad_access")).matchesXcodeEvent(event))
        #expect(!IssueMatcher(criteria: .init(type: "FATAL")).matchesXcodeEvent(event))
        #expect(IssueMatcher(criteria: .init(sinceVersion: "6.10.0")).matchesXcodeEvent(event))
        #expect(!IssueMatcher(criteria: .init(sinceVersion: "7.0.0")).matchesXcodeEvent(event))
        #expect(IssueMatcher(criteria: .init(appVersion: "6.16.0")).matchesXcodeEvent(event))
        #expect(IssueMatcher(criteria: .init(minEvents: 1)).matchesXcodeEvent(event))
        #expect(!IssueMatcher(criteria: .init(minEvents: 2)).matchesXcodeEvent(event))
        #expect(IssueMatcher(criteria: .init(file: "Checkout.swift", symbol: "Checkout.pay()")).matchesXcodeEvent(event))
    }

    @Test("event-only filters exclude every Xcode crash")
    func xcodeExcludedByEventOnlyFilters() {
        let event = xcodeEvent()
        #expect(!IssueMatcher(criteria: .init(userId: "u")).matchesXcodeEvent(event))
        #expect(!IssueMatcher(criteria: .init(domain: "d")).matchesXcodeEvent(event))
        #expect(!IssueMatcher(criteria: .init(userInfoKey: ["k"])).matchesXcodeEvent(event))
    }
}
