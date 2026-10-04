//
//  GroupingTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore

@Suite("Crash grouping")
struct GroupingTests {
    private func firebase(_ id: String, title: String, events: Int = 0, users: Int = 0) -> CrashIssue {
        CrashIssue(providerId: id, title: title, subtitle: "EXC_BAD_ACCESS", exceptionType: "FATAL",
        eventsCount: events, impactedUsersCount: users)
    }

    private func local(_ id: String, symbols: [(String, String)]) -> XcodeCrash {
        let frames = symbols.enumerated().map { Frame(index: $0.offset, binaryName: $0.element.0, symbol: $0.element.1, address: 0) }
        let event = CrashEvent(
            id: id, source: .xcode, crashedThreadIndex: 0,
            exception: ExceptionInfo(exceptionType: "EXC_BAD_ACCESS"),
            frames: frames
        )
        return XcodeCrash(event: event, filePath: "/\(id).crash", fileMtime: Date(timeIntervalSince1970: 0), fileSize: 1)
    }

    @Test("Firebase title parses to culprit symbol + module")
    func signatureFromTitle() throws {
        let sig = try #require(CrashSignature.fromTitle("[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)"))
        #expect(sig.symbol == "blurdetectionservice.classifywithml(_:)")
        #expect(sig.module == "Core")

        let noFile = try #require(CrashSignature.fromTitle("[Core] closure #1 in FileStorage.save(assets:)"))
        #expect(noFile.symbol == "closure #1 in filestorage.save(assets:)")
    }

    @Test("local signature skips runtime plumbing to the top app frame")
    func signatureFromFrames() throws {
        let sig = try #require(CrashSignature.fromFrames([
            Frame(index: 0, binaryName: "libswiftCore.dylib", symbol: "_swift_release_dealloc", address: 0),
            Frame(index: 1, binaryName: "Core", symbol: "BlurDetectionService.classifyWithML(_:)", address: 0)
        ]))
        #expect(sig.symbol == "blurdetectionservice.classifywithml(_:)")
        #expect(sig.module == "Core")
    }

    @Test("\"specialized\" decoration is stripped so it groups with the plain symbol")
    func normalizesDecorations() {
        #expect(CrashSignature.normalize("specialized Request.start(in:)") == "request.start(in:)")
    }

    @Test("same culprit across Firebase issues + a local repro collapses to one cross-source group")
    func groupsByCulprit() throws {
        let groups = CrashGrouper().group(
            local: [local("L1", symbols: [("libswiftCore.dylib", "abort"), ("Core", "BlurDetectionService.classifyWithML(_:)")])],
            firebase: [
                firebase("F1", title: "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)", events: 90),
                firebase("F2", title: "[Core] BlurDetectorV3.swift - BlurDetectionService.classifyWithML(_:)", events: 79),
                firebase("F3", title: "[SmartlookAnalytics] Properties.__deallocating_deinit", events: 350)
            ]
        )
        // Blur group (2 FB + 1 local) and the Smartlook group.
        let blur = try #require(groups.first { $0.symbol == "blurdetectionservice.classifywithml(_:)" })
        #expect(blur.firebase.count == 2)
        #expect(blur.xcode.count == 1)
        #expect(blur.isCrossSource)
        #expect(blur.totalEvents == 169)
        // Cross-source group sorts ahead of the firebase-only one.
        #expect(groups.first?.symbol == "blurdetectionservice.classifywithml(_:)")
    }

    @Test("duplicate local crashes (same incident id) are de-duped")
    func dedupesLocal() {
        let dup = local("SAME", symbols: [("App", "foo()")])
        let groups = CrashGrouper().group(local: [dup, dup, dup], firebase: [])
        #expect(groups.count == 1)
        #expect(groups[0].xcode.count == 1)
    }
}
