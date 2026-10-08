import Foundation
import Testing
@testable import xcrashlytics

@Suite("symbolication advisor")
struct SymbolicationAdvisorTests {
    private func image(_ name: String, _ uuid: String, _ path: String) -> BinaryImage {
        BinaryImage(name: name, uuid: uuid, loadAddress: 0, arch: "arm64", path: path)
    }

    private func crash(_ frames: [StackFrame], images: [BinaryImage], id: String = "XC-1") -> XcodeCrash {
        let event = CrashEvent(
            id: id, source: .xcode, crashedThreadIndex: 0,
            exception: ExceptionDescriptor(exceptionType: "EXC_CRASH"), frames: frames, binaryImages: images)
        return XcodeCrash(event: event, filePath: "/\(id).crash", fileMtime: Date(timeIntervalSince1970: 0), fileSize: 1)
    }

    private let app = "/private/var/containers/Bundle/Application/A/MyApp.app/MyApp"

    @Test("app-owned image detection")
    func appOwned() {
        #expect(SymbolicationAdvisor.isAppOwned(image("MyApp", "U1", app)))
        #expect(SymbolicationAdvisor.isAppOwned(image("Ext", "U1", "/var/containers/Bundle/Application/A/MyApp.app/PlugIns/Ext.appex/Ext")))
        #expect(!SymbolicationAdvisor.isAppOwned(image("libsystem", "U2", "/usr/lib/libsystem.dylib")))
        #expect(!SymbolicationAdvisor.isAppOwned(image("UIKit", "U3", "/System/Library/UIKit")))
        // Not under /System/ or /usr/lib/, but still OS code.
        #expect(!SymbolicationAdvisor.isAppOwned(image("libobjc", "U4", "/private/preboot/Cryptexes/OS/usr/lib/libobjc.A.dylib")))
        // Simulator runtimes live inside Xcode.app but are OS code.
        let simulatorRuntime = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform"
            + "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot"
            + "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
        #expect(!SymbolicationAdvisor.isAppOwned(image("SwiftUI", "U5", simulatorRuntime)))
    }

    @Test("a fully symbolicated crash needs no dSYM hint, however many app images it lists")
    func symbolicatedCrashHasNoHint() {
        let images = [image("MyApp", "U1", app), image("SDK", "U2", "/x/MyApp.app/Frameworks/SDK.framework/SDK")]
        let frames = [StackFrame(index: 0, binaryName: "MyApp", symbol: "main", address: 1, imageUUID: "U1", isSymbolicated: true)]
        #expect(SymbolicationAdvisor.hint(for: [crash(frames, images: images)]) == nil)
    }

    @Test("only app-owned images behind unsymbolicated crashed-thread frames are counted")
    func countsOnlyMissingAppImages() {
        let images = [
            image("MyApp", "U1", app),
            image("SDK", "U2", "/x/MyApp.app/Frameworks/SDK.framework/SDK"),
            image("Unused", "U3", "/x/MyApp.app/Frameworks/Unused.framework/Unused"),
            image("UIKit", "U4", "/System/Library/Frameworks/UIKit.framework/UIKit")
        ]
        let frames = [
            StackFrame(index: 0, binaryName: "UIKit", symbol: nil, address: 1, imageUUID: "U4"),
            StackFrame(index: 1, binaryName: "SDK", symbol: "0x1000", address: 2, imageUUID: "U2"),
            StackFrame(index: 2, binaryName: "MyApp", symbol: "main", address: 3, imageUUID: "U1", isSymbolicated: true)
        ]
        #expect(SymbolicationAdvisor.hint(for: [crash(frames, images: images)])
            == "1 app dSYM UUID(s) may be needed for 1 Xcode crash(es).")
        let second = crash(frames, images: images, id: "XC-2")
        #expect(SymbolicationAdvisor.hint(for: [crash(frames, images: images), second])
            == "1 app dSYM UUID(s) may be needed for 2 Xcode crash(es).")
    }

    @Test("the real Organizer report (mostly symbolicated) only asks for the SDK image its raw frames use")
    func realReport() throws {
        let event = try CrashReportParserRegistry(fileStore: InMemoryFileStore())
            .parse(text: XcodeFixtures.text("organizer-real.crash"), path: "r.crash").event
        let hint = SymbolicationAdvisor.hint(for: [crash(event.frames, images: event.binaryImages)])
        #expect(hint == "1 app dSYM UUID(s) may be needed for 1 Xcode crash(es).")
    }
}
