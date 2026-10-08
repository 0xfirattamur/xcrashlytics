import Foundation
import Testing
@testable import xcrashlytics

@Suite("Renderers")
struct RendererTests {
    private func event(
        _ id: String, source: CrashSource, bundle: String? = "com.x.app", exc: String = "EXC_BAD_ACCESS"
    ) -> CrashEvent {
        CrashEvent(
            id: id, source: source, bundleId: bundle,
            crashedThreadIndex: 0,
            exception: ExceptionDescriptor(exceptionType: exc),
            frames: [],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func detail(
        _ event: CrashEvent, issue: CrashIssue? = nil, activity: IssueActivitySummary? = nil
    ) -> CrashDetail {
        CrashDetail(event: event, issue: issue, activity: activity)
    }

    private func json(_ detail: CrashDetail) throws -> String {
        try ShowPresenter().render(detail, format: .json).body
    }

    private func text(_ detail: CrashDetail) -> String {
        CrashDetailTextRenderer().render(detail, includeBreadcrumbs: false)
    }

    @Test("text frames align symbols in one column, and long binary names are not truncated")
    func frameColumnsAlign() {
        let renderer = CrashDetailTextRenderer()
        let short = renderer.renderFrame(StackFrame(index: 0, binaryName: "UIKit", symbol: "UIApplicationMain"))
        let long = renderer.renderFrame(StackFrame(index: 12, binaryName: "ExampleApp", symbol: "main", address: 0x1000))
        let huge = String(repeating: "N", count: 40)
        let overflow = renderer.renderFrame(StackFrame(index: 1, binaryName: huge, symbol: "f"))

        #expect(short == "  0  UIKit" + String(repeating: " ", count: 27) + "  UIApplicationMain")
        #expect(long == " 12  ExampleApp" + String(repeating: " ", count: 22) + "  0x0000000000001000  main")
        #expect(overflow == "  1  \(huge)  f")
    }

    @Test("plain text prints the time in UTC with an explicit marker, whatever the local zone")
    func textTimeIsUTC() {
        let output = text(detail(event("L1", source: .xcode)))
        #expect(output.contains("Time:      2023-11-14 22:13 UTC"))
    }

    @Test("plain text for no groups says so")
    func textNoGroups() {
        #expect(GroupsTextRenderer().render([]) == "No crashes found.\n")
    }

    @Test("frames without addresses omit the address column")
    func frameWithoutAddress() {
        var record = event("F1", source: .firebase)
        record.frames = [
            StackFrame(index: 0, binaryName: "MyApp", symbol: "doWork()", file: "Work.swift", line: 12, address: nil)
        ]
        let output = text(detail(record))
        #expect(output.contains("doWork()"))
        #expect(output.contains("(Work.swift:12)"))
        #expect(!output.contains("0x0000000000000000"))
    }

    @Test("JSON detail omits address for frames without one")
    func jsonFrameWithoutAddress() throws {
        var record = event("F1", source: .firebase)
        record.frames = [
            StackFrame(index: 0, binaryName: "MyApp", symbol: "doWork()", address: nil)
        ]
        let output = try json(detail(record))
        let frame = try #require(Envelope(output).data["frames"]?[0]?.object)
        #expect(frame["symbol"]?.string == "doWork()")
        #expect(frame["address"] == nil)
    }

    @Test("plain text detail renders sampled activity header")
    func textDetailActivityHeader() {
        let record = event("F1", source: .firebase)
        let issue = CrashIssue(
            providerId: "F1", exceptionType: "EXC_BAD_ACCESS", eventsCount: 737, impactedUsersCount: 120)
        let activity = IssueActivitySummary(
            sampledEvents: 100,
            firstEventAt: "2026-06-01T08:00:00Z",
            lastEventAt: "2026-06-10T08:00:00Z",
            osSpread: [SpreadCount(name: "iOS 26.4.1", count: 62), SpreadCount(name: "iOS 26.3.0", count: 38)],
            deviceSpread: [SpreadCount(name: "iPhone 17 Pro Max", count: 40)],
            distinctUsers: 14
        )
        let output = text(detail(record, issue: issue, activity: activity))
        #expect(output.contains("Impact:    737 events / 120 users"))
        #expect(output.contains("Sampled:   newest 100 events, 2026-06-01 → 2026-06-10, 14 users"))
        #expect(output.contains("OS:        iOS 26.4.1 ×62, iOS 26.3.0 ×38"))
        #expect(output.contains("Devices:   iPhone 17 Pro Max ×40"))
    }
}
