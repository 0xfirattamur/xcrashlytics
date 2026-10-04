//
//  RendererTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore
@testable import xcrashlytics

@Suite("Renderers")
struct RendererTests {
    private func event(_ id: String, source: CrashSource, bundle: String? = "com.x.app", exc: String = "EXC_BAD_ACCESS") -> CrashEvent {
        CrashEvent(
            id: id, source: source, bundleId: bundle,
            crashedThreadIndex: 0,
            exception: ExceptionInfo(exceptionType: exc),
            frames: [],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func issue(_ id: String) -> CrashIssue {
        CrashIssue(providerId: id, exceptionType: "EXC_BAD_ACCESS")
    }

    private func xcode(_ id: String) -> XcodeCrash {
        XcodeCrash(
            event: event("XC-\(id)", source: .xcode),
            filePath: "/p/\(id).ips",
            fileMtime: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: 0
        )
    }

    @Test("JSON renders crash detail")
    func jsonDetail() throws {
        let r = JSONRenderer()
        let out = try r.renderDetail(event("F1", source: .firebase))
        let data = try Envelope(out).data
        #expect(data["source"]?.string == "firebase")
        #expect(data["id"]?.string == "F1")
    }

    @Test("JSON renders groups with limit")
    func jsonGroups() throws {
        let r = JSONRenderer()
        let groups = [
            CrashGroup(symbol: "first", module: "App", firebase: [issue("F1")], xcode: [xcode("L1")]),
            CrashGroup(symbol: "second", module: "App", firebase: [issue("F2")], xcode: [])
        ]
        let out = try r.renderGroups(groups, limit: 1)
        let rendered = try #require(Envelope(out).data["groups"]?.array)
        #expect(rendered.count == 1)
        #expect(rendered.first?["symbol"]?.string == "first")
        #expect(rendered.first?["crossSource"]?.bool == true)
    }

    @Test("plain text renders crash detail")
    func textDetail() {
        let out = PlainTextRenderer().renderDetail(event("L1", source: .xcode))
        #expect(out.contains("ID:        L1"))
        #expect(out.contains("Thread 0 (crashed):"))
    }

    @Test("frames without addresses omit the address column")
    func frameWithoutAddress() {
        var record = event("F1", source: .firebase)
        record.frames = [
            Frame(index: 0, binaryName: "MyApp", symbol: "doWork()", file: "Work.swift", line: 12, address: nil)
        ]
        let out = PlainTextRenderer().renderDetail(record)
        #expect(out.contains("doWork()"))
        #expect(out.contains("(Work.swift:12)"))
        #expect(!out.contains("0x0000000000000000"))
    }

    @Test("frames with addresses render the raw pointer")
    func frameWithAddress() {
        var record = event("L1", source: .xcode)
        record.frames = [
            Frame(index: 0, binaryName: "MyApp", symbol: "doWork()", address: 0x1A2B)
        ]
        let out = PlainTextRenderer().renderDetail(record)
        #expect(out.contains("0x0000000000001a2b"))
    }

    @Test("JSON detail omits address for frames without one")
    func jsonFrameWithoutAddress() throws {
        var record = event("F1", source: .firebase)
        record.frames = [
            Frame(index: 0, binaryName: "MyApp", symbol: "doWork()", address: nil)
        ]
        let out = try JSONRenderer().renderDetail(record)
        let frame = try #require(Envelope(out).data["frames"]?[0]?.object)
        #expect(frame["symbol"]?.string == "doWork()")
        #expect(frame["address"] == nil)
    }

    @Test("plain text detail renders sampled activity header")
    func textDetailActivityHeader() {
        let record = event("F1", source: .firebase)
        let issue = CrashIssue(providerId: "F1", exceptionType: "EXC_BAD_ACCESS", eventsCount: 737, impactedUsersCount: 120)
        let activity = IssueActivitySummary(
            sampledEvents: 100,
            firstEventAt: "2026-06-01T08:00:00Z",
            lastEventAt: "2026-06-10T08:00:00Z",
            osSpread: [SpreadCount(name: "iOS 26.4.1", count: 62), SpreadCount(name: "iOS 26.3.0", count: 38)],
            deviceSpread: [SpreadCount(name: "iPhone 17 Pro Max", count: 40)],
            distinctUsers: 14
        )
        let out = PlainTextRenderer().renderDetail(record, issue: issue, activity: activity)
        #expect(out.contains("Impact:    737 events / 120 users"))
        #expect(out.contains("Sampled:   newest 100 events, 2026-06-01 → 2026-06-10, 14 users"))
        #expect(out.contains("OS:        iOS 26.4.1 ×62, iOS 26.3.0 ×38"))
        #expect(out.contains("Devices:   iPhone 17 Pro Max ×40"))
    }

    @Test("JSON detail embeds activity summary when present")
    func jsonDetailActivity() throws {
        let activity = IssueActivitySummary(
            sampledEvents: 3,
            firstEventAt: nil,
            lastEventAt: "2026-06-10T08:00:00Z",
            osSpread: [],
            deviceSpread: [],
            distinctUsers: nil
        )
        let out = try JSONRenderer().renderDetail(event("F1", source: .firebase), activity: activity)
        let data = try Envelope(out).data
        #expect(data["activity"]?["sampledEvents"]?.int == 3)
        #expect(data["source"]?.string == "firebase")
    }

    @Test("plain text renders groups")
    func textGroups() {
        let group = CrashGroup(
            symbol: "analyzeBlur",
            module: "App",
            firebase: [issue("F1")],
            xcode: [xcode("L1")]
        )
        let out = PlainTextRenderer().renderGroups([group])
        #expect(out.contains("analyzeBlur"))
        #expect(out.contains("FB-F1"))
        #expect(out.contains("XC-L1"))
    }
}
