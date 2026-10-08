import Foundation
import Testing
@testable import xcrashlytics

@Suite("Crash grouping")
struct GroupingTests {
    private func firebase(_ id: String, title: String, events: Int = 0, users: Int = 0) -> CrashIssue {
        CrashIssue(providerId: id, title: title, subtitle: "EXC_BAD_ACCESS", exceptionType: "FATAL",
        eventsCount: events, impactedUsersCount: users)
    }

    private func local(_ id: String, symbols: [(String, String)]) -> XcodeCrash {
        let frames = symbols.enumerated().map { StackFrame(index: $0.offset, binaryName: $0.element.0, symbol: $0.element.1, address: 0) }
        let event = CrashEvent(
            id: id, source: .xcode, crashedThreadIndex: 0,
            exception: ExceptionDescriptor(exceptionType: "EXC_BAD_ACCESS"),
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
        #expect(noFile.symbol == "filestorage.save(assets:)")
    }

    @Test("non-fatal titles at the Crashlytics SDK frame carry no signature, so unrelated non-fatals don't merge")
    func sdkTitlesDoNotGroup() {
        let title = "[Core] FIRCLSNonFatalError.m - -[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]"
        #expect(CrashSignature.fromTitle(title) == nil)
        let groups = CrashGrouper().group(local: [], firebase: [firebase("N1", title: title), firebase("N2", title: title)])
        #expect(groups.count == 2)
    }

    @Test("local signature skips runtime plumbing to the top app frame")
    func signatureFromFrames() throws {
        let sig = try #require(CrashSignature.fromFrames([
            StackFrame(index: 0, binaryName: "libswiftCore.dylib", symbol: "_swift_release_dealloc", address: 0),
            StackFrame(index: 1, binaryName: "Core", symbol: "BlurDetectionService.classifyWithML(_:)", address: 0)
        ]))
        #expect(sig.symbol == "blurdetectionservice.classifywithml(_:)")
        #expect(sig.module == "Core")
    }

    @Test("compiler decorations are stripped in any order so variants group with the plain symbol")
    func normalizesDecorations() {
        let plain = "request.start(in:)"
        for decorated in [
            "specialized Request.start(in:)",
            "static specialized Request.start(in:)",
            "specialized static @objc Request.start(in:)",
            "closure #1 in Request.start(in:)",
            "closure #2 in closure #1 in Request.start(in:)",
            "implicit closure #1 in Request.start(in:)",
            "partial apply for closure #1 in Request.start(in:)",
            "merged Request.start(in:)",
            "Request.start(in:) [inlined]",
            "Request<A>.start(in:)",
            "Request<Dictionary<String, Array<Int>>>.start(in:)",
            "generic specialization <Swift.Int> of Request.start(in:)"
        ] {
            #expect(CrashSignature.normalize(decorated) == plain, "\(decorated)")
        }
    }

    @Test("normalization keeps distinct symbols distinct and operators intact")
    func normalizationKeepsDistinctSymbols() {
        #expect(CrashSignature.normalize("-[Foo bar:]") == "-[foo bar:]")
        #expect(CrashSignature.normalize("-[Foo bar:]") != CrashSignature.normalize("-[Foo baz:]"))
        #expect(CrashSignature.normalize("static Int.< infix(_:_:)") == "int.< infix(_:_:)")
        #expect(CrashSignature.normalize("$s6MyApp3FooV3baryyF") == "$s6myapp3foov3baryyf")
    }

    @Test("unsymbolicated frames never become a signature — the load address is per-launch noise")
    func addressOnlySymbolsAreNotSignatures() {
        let raw = [
            StackFrame(index: 0, binaryName: "App", symbol: "0x102f70000", address: 1),
            StackFrame(index: 1, binaryName: "App", symbol: nil, address: 2)
        ]
        #expect(CrashSignature.fromFrames(raw) == nil)
        // Same crash, different ASLR slide: still no signature, so no accidental group by slide.
        let slid = [StackFrame(index: 0, binaryName: "App", symbol: "0x1049b0000", address: 1)]
        #expect(CrashSignature.fromFrames(slid) == nil)
    }

    @Test("a crash with only unsymbolicated app frames stays its own group instead of merging by load address")
    func unsymbolicatedCrashesStaySeparate() throws {
        func crash(_ id: String, slide: String) throws -> XcodeCrash {
            let text = try XcodeFixtures.text("unsymbolicated.crash")
                .replacingOccurrences(of: "0x102f70000", with: slide)
                .replacingOccurrences(of: "99999999", with: id)
            let event = try CrashReportParserRegistry(fileStore: InMemoryFileStore()).parse(text: text, path: "\(id).crash").event
            return XcodeCrash(event: event, filePath: "/\(id).crash", fileMtime: Date(timeIntervalSince1970: 0), fileSize: 1)
        }
        let first = try crash("AAAAAAAA", slide: "0x102f70000")
        let second = try crash("BBBBBBBB", slide: "0x104110000")
        // The only symbolicated non-noise frame is UIKit's UIApplicationMain — never the slide.
        let signature = try #require(CrashSignature.of(first.event))
        #expect(signature.symbol == "uiapplicationmain")
        let groups = CrashGrouper().group(local: [first, second], firebase: [])
        #expect(groups.map(\.symbol) == ["uiapplicationmain"])
        #expect(groups.allSatisfy { !$0.symbol.hasPrefix("0x") })
    }

    @Test("culprit prefers the app-owned frame over system frames that run earlier in the stack")
    func culpritPrefersAppOwnedFrame() throws {
        let images = [
            BinaryImage(name: "Foundation", uuid: "U1", loadAddress: 0, arch: "arm64",
                path: "/System/Library/Frameworks/Foundation.framework/Foundation"),
            BinaryImage(name: "MyApp", uuid: "U2", loadAddress: 0, arch: "arm64",
                path: "/private/var/containers/Bundle/Application/A/MyApp.app/MyApp"),
            BinaryImage(name: "AdSDK", uuid: "U3", loadAddress: 0, arch: "arm64",
                path: "/private/var/containers/Bundle/Application/A/MyApp.app/Frameworks/AdSDK.framework/AdSDK")
        ]
        let frames = [
            StackFrame(index: 0, binaryName: "Foundation", symbol: "-[NSObject doesNotRecognizeSelector:]", address: 1, imageUUID: "U1"),
            StackFrame(index: 1, binaryName: "AdSDK", symbol: nil, address: 2, imageUUID: "U3"),
            StackFrame(index: 2, binaryName: "MyApp", symbol: "Checkout.pay()", address: 3, imageUUID: "U2"),
            StackFrame(index: 3, binaryName: "Foundation", symbol: "NSRunLoop.run", address: 4, imageUUID: "U1")
        ]
        let signature = try #require(CrashSignature.fromFrames(frames, images: images))
        #expect(signature.symbol == "checkout.pay()")
        #expect(signature.module == "MyApp")
        // With no app-owned symbolicated frame, the first non-noise symbolicated frame wins.
        let systemOnly = try #require(CrashSignature.fromFrames([frames[0], frames[3]], images: images))
        #expect(systemOnly.symbol == "-[nsobject doesnotrecognizeselector:]")
    }

    @Test("the real Organizer crash is blamed on app code, not a Foundation frame above the SDK")
    func realOrganizerCrashCulprit() throws {
        let event = try CrashReportParserRegistry(fileStore: InMemoryFileStore())
            .parse(text: XcodeFixtures.text("organizer-real.crash"), path: "r.crash").event
        let signature = try #require(CrashSignature.of(event))
        let culprit = try #require(event.frames.first { $0.symbol.map { CrashSignature.normalize($0) == signature.symbol } == true })
        let image = try #require(SymbolicationAdvisor.image(for: culprit, in: event.binaryImages))
        #expect(SymbolicationAdvisor.isAppOwned(image))
    }

    @Test("groups with equal impact order deterministically by symbol")
    func deterministicOrder() {
        let issues = ["Zeta.run()", "Alpha.run()", "Mid.run()"].enumerated().map {
            firebase("F\($0.offset)", title: "[M] \($0.element)", events: 5)
        }
        let forward = CrashGrouper().group(local: [], firebase: issues).map(\.symbol)
        let reversed = CrashGrouper().group(local: [], firebase: issues.reversed()).map(\.symbol)
        #expect(forward == ["alpha.run()", "mid.run()", "zeta.run()"])
        #expect(reversed == forward)
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
