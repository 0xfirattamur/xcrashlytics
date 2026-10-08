import Testing
@testable import xcrashlytics

@Suite("event scan plan and issue id list")
struct EventScanPlanTests {
    @Test("a user filter scans at least 50 events; otherwise just the limit")
    func depth() {
        #expect(EventScanPlan(limit: 3, latest: false, userFiltered: true).depth == 50)
        #expect(EventScanPlan(limit: 80, latest: false, userFiltered: true).depth == 80)
        #expect(EventScanPlan(limit: nil, latest: false, userFiltered: false).depth == 10)
        #expect(EventScanPlan(limit: 3, latest: true, userFiltered: false).requestedLimit == 1)
    }

    @Test("truncation is reported only for user-filtered scans that filled the depth")
    func truncation() {
        let filtered = EventScanPlan(limit: 3, latest: false, userFiltered: true)
        #expect(filtered.truncationMessage(issueId: "FB-I1", fetchedCount: 50) != nil)
        #expect(filtered.truncationMessage(issueId: "FB-I1", fetchedCount: 49) == nil)
        #expect(EventScanPlan(limit: 3, latest: false, userFiltered: false)
            .truncationMessage(issueId: "FB-I1", fetchedCount: 3) == nil)
    }

    @Test("issue ids are canonical, trimmed and deduplicated in first-seen order")
    func idList() throws {
        #expect(try IssueIdList.parse(["a, FB-b", "A,b ,c"]) == ["FB-a", "FB-b", "FB-A", "FB-c"])
        #expect(throws: InvalidInputError.self) { try IssueIdList.parse([nil, " , "]) }
    }
}
