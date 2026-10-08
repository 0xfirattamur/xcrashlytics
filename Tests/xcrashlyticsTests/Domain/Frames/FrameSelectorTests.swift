import Foundation
import Testing
@testable import xcrashlytics

@Suite("FrameSelector")
struct FrameSelectorTests {
    private let selector = FrameSelector()

    private func event(_ json: String) throws -> CrashlyticsEvent {
        try CrashlyticsEventDTOMapper().event(from: JSONDecoder().decode(CrashlyticsDTO.Event.self, from: Data(json.utf8)))
    }

    private func symbols(_ frames: [CrashlyticsFrame]) -> [String?] { frames.map(\.symbol) }

    // MARK: - Filtering

    @Test("appFramesOnly and noSystemFrames keep different sets")
    func filterOptions() throws {
        let event = try event(#"""
        {"threads":[{"crashed":true,"frames":[
          {"symbol":"FIRCLSNonFatalError","file":"FIRCLSNonFatalError.m"},
          {"symbol":"Alamofire.request","file":"Session.swift","owner":"VENDOR","library":"Alamofire"},
          {"symbol":"CrashlyticsLogger.log","file":"L.swift","owner":"DEVELOPER","library":"MyApp"},
          {"symbol":"_dispatch","library":"libdispatch.dylib","owner":"SYSTEM"},
          {"symbol":"MyApp.main","file":"main.swift","owner":"DEVELOPER","library":"MyApp"},
          {"address":"6846248376","owner":"DEVELOPER"}
        ]}]}
        """#)
        let app = selector.filteredFrames(from: event, filter: FrameFilter(appFramesOnly: true))
        #expect(symbols(app) == ["CrashlyticsLogger.log", "MyApp.main"])
        let noSystem = selector.filteredFrames(from: event, filter: FrameFilter(noSystemFrames: true))
        #expect(symbols(noSystem) == ["Alamofire.request", "CrashlyticsLogger.log", "MyApp.main", nil])
    }

    @Test("appLibraries make a profile's first-party framework count for --app-frames-only")
    func appLibrariesInFilter() throws {
        let event = try event(#"""
        {"threads":[{"crashed":true,"frames":[
          {"symbol":"FIRCLSProcessRecordAllThreads","library":"KeyboardCore","owner":"THIRD_PARTY"},
          {"symbol":"Engine.run()","library":"KeyboardCore","owner":"THIRD_PARTY"},
          {"symbol":"KeyboardKit.type()","library":"KeyboardKit","owner":"THIRD_PARTY"}
        ]}]}
        """#)
        let filter = FrameFilter(appFramesOnly: true)
        #expect(symbols(selector.filteredFrames(from: event, filter: filter)).isEmpty)
        let configured = FrameSelector(classifier: FrameClassifier(appLibraries: ["KeyboardCore"]))
        #expect(symbols(configured.filteredFrames(from: event, filter: filter)) == ["Engine.run()"])
    }

    // MARK: - Thread choice

    private let twoThreads = #"""
    {"threads":[
      {"title":"first","frames":[{"symbol":"first"}]},
      {"title":"blamed","blamed":true,"frames":[{"symbol":"blamedThread"}]},
      {"title":"crashed","crashed":true,"frames":[{"symbol":"crashedThread"}]}
    ]}
    """#

    @Test("thread choice: crashed, then blamed, then first")
    func threadChoice() throws {
        #expect(symbols(selector.stackFrames(from: try event(twoThreads))) == ["crashedThread"])
        let noCrashed = try event(#"""
        {"threads":[{"frames":[{"symbol":"first"}]},{"blamed":true,"frames":[{"symbol":"blamedThread"}]}]}
        """#)
        #expect(symbols(selector.stackFrames(from: noCrashed)) == ["blamedThread"])
        let plain = try event(#"{"threads":[{"frames":[{"symbol":"a"}]},{"frames":[{"symbol":"b"}]}]}"#)
        #expect(symbols(selector.stackFrames(from: plain)) == ["a"])
    }

    @Test("a crashed thread without frames does not hide the others")
    func emptyCrashedThread() throws {
        let event = try event(#"{"threads":[{"crashed":true,"frames":[]},{"frames":[{"symbol":"b"}]}]}"#)
        #expect(symbols(selector.stackFrames(from: event)) == ["b"])
    }

    @Test("crashingThreadOnly returns the crashed thread, or nothing")
    func crashingThreadOnly() throws {
        let crashed = try event(twoThreads)
        #expect(symbols(selector.stackFrames(from: crashed, crashingThreadOnly: true)) == ["crashedThread"])
        #expect(crashed.hasCrashedThread)

        let none = try event(#"{"threads":[{"frames":[{"symbol":"a"}]},{"blamed":true,"frames":[{"symbol":"b"}]}]}"#)
        #expect(selector.stackFrames(from: none, crashingThreadOnly: true).isEmpty)
        #expect(selector.frames(from: none, filter: FrameFilter(crashingThreadOnly: true)).isEmpty)
        #expect(!none.hasCrashedThread)
        #expect(symbols(selector.stackFrames(from: none)) == ["b"])
    }

    @Test("frames fall back to exceptions, then to Apple errors[] preferring the blamed one")
    func fallbackSources() throws {
        let android = try event(#"{"exceptions":[{"frames":[{"symbol":"ex"}]}]}"#)
        #expect(symbols(selector.stackFrames(from: android)) == ["ex"])

        let apple = try event(#"""
        {"errors":[
          {"title":"a","frames":[{"symbol":"plain"}]},
          {"title":"b","blamed":true,"frames":[{"symbol":"blamedError"}]}
        ]}
        """#)
        #expect(symbols(selector.stackFrames(from: apple)) == ["blamedError"])
        #expect(symbols(selector.frames(from: apple).map { CrashlyticsFrame(symbol: $0.symbol) }) == ["blamedError"])
        #expect(apple.errors.count == 2)
    }

    // MARK: - Blame frame

    @Test("blame frame is prepended once, matched on symbol, file, and line")
    func blameDedup() throws {
        let duplicate = try event(#"""
        {"blameFrame":{"symbol":"x","file":"X.swift","line":"1"},
         "threads":[{"crashed":true,"frames":[{"symbol":"x","file":"X.swift","line":"1","library":"MyApp"},{"symbol":"y"}]}]}
        """#)
        #expect(symbols(selector.stackFrames(from: duplicate)) == ["x", "y"])

        let missing = try event(#"""
        {"blameFrame":{"symbol":"blame","file":"B.swift","line":"3"},
         "threads":[{"crashed":true,"frames":[{"symbol":"y"}]}]}
        """#)
        #expect(symbols(selector.stackFrames(from: missing)) == ["blame", "y"])

        let only = try event(#"{"blameFrame":{"symbol":"blame","file":"B.swift"}}"#)
        #expect(symbols(selector.stackFrames(from: only)) == ["blame"])
    }

    @Test("a symbol-less blame frame keeps its library and never marks other symbol-less frames as blamed")
    func symbollessBlameFrame() throws {
        let event = try event(#"""
        {"blameFrame":{"address":"620768","library":"CoreFoundation","owner":"PLATFORM","blamed":true},
         "threads":[{"crashed":true,"frames":[
           {"symbol":"a","library":"MyApp"},
           {"address":"6846248376","owner":"DEVELOPER"},
           {"address":"620768","library":"CoreFoundation"}
         ]}]}
        """#)
        let stack = selector.stackFrames(from: event)
        // The thread already holds the blame frame (same library and address): no duplicate.
        #expect(stack.map(\.library) == ["MyApp", nil, "CoreFoundation"])
        #expect(stack.map { selector.isBlamed($0, in: event) } == [false, false, true])
        #expect(selector.frames(from: event).map(\.binaryName) == ["MyApp", "?", "CoreFoundation"])

        let absent = try self.event(#"""
        {"blameFrame":{"address":"620768","library":"CoreFoundation","blamed":true},
         "threads":[{"crashed":true,"frames":[{"address":"1","library":"Other"}]}]}
        """#)
        #expect(selector.stackFrames(from: absent).map(\.library) == ["CoreFoundation", "Other"])
    }

    @Test("blamedFrame prefers Crashlytics' blame, then blamed frames, then the first app frame")
    func blamedFrameFallback() throws {
        let withBlame = try event(#"{"blameFrame":{"symbol":"b"},"threads":[{"frames":[{"symbol":"t","blamed":true}]}]}"#)
        #expect(selector.blamedFrame(from: withBlame)?.symbol == "b")

        let flagged = try event(#"{"threads":[{"frames":[{"symbol":"sys","library":"libdispatch.dylib"},{"symbol":"t","blamed":true}]}]}"#)
        #expect(selector.blamedFrame(from: flagged)?.symbol == "t")

        let firstApp = try event(#"""
        {"threads":[{"frames":[
          {"symbol":"_dispatch","library":"libdispatch.dylib","owner":"SYSTEM"},
          {"symbol":"MyApp.go","file":"Go.swift","library":"MyApp","owner":"DEVELOPER"}
        ]}]}
        """#)
        #expect(selector.blamedFrame(from: firstApp)?.symbol == "MyApp.go")

        let appLibrary = try event(#"""
        {"threads":[{"frames":[
          {"symbol":"_dispatch","library":"libdispatch.dylib","owner":"SYSTEM"},
          {"symbol":"Engine.run()","library":"KeyboardCore","owner":"THIRD_PARTY"},
          {"symbol":"Other.go()","library":"Other","owner":"THIRD_PARTY"}
        ]}]}
        """#)
        #expect(selector.blamedFrame(from: appLibrary)?.symbol == "_dispatch")
        #expect(FrameSelector(classifier: FrameClassifier(appLibraries: ["keyboardcore"])).blamedFrame(from: appLibrary)?.symbol == "Engine.run()")

        let nothing = try event(#"{"threads":[{"frames":[{"symbol":"a"},{"symbol":"b"}]}]}"#)
        #expect(selector.blamedFrame(from: nothing)?.symbol == "a")
    }

    @Test("a non-fatal's blame skips the Crashlytics SDK frames to the app code that recorded the error")
    func blamedFrameSkipsCrashlyticsSDK() throws {
        let nonFatal = try event(#"""
        {"blameFrame":{"symbol":"-[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]","file":"FIRCLSNonFatalError.m"},
         "threads":[{"frames":[
           {"symbol":"-[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]","file":"FIRCLSNonFatalError.m","library":"Core"},
           {"symbol":"-[FIRCrashlytics recordError:userInfo:]","file":"FIRCrashlytics.m","library":"Core"},
           {"symbol":"BlurMLClassifier.recordFailure(error:message:)","file":"BlurMLClassifier.swift","library":"Core"}
         ]}]}
        """#)
        #expect(selector.blamedFrame(from: nonFatal)?.symbol == "BlurMLClassifier.recordFailure(error:message:)")
    }

    // MARK: - Indices and native details

    @Test("filtered frames keep their original stack index")
    func originalIndices() throws {
        let event = try event(#"""
        {"threads":[{"crashed":true,"frames":[
          {"symbol":"FIRCLSx","file":"FIRCLSx.m"},
          {"symbol":"_dispatch","library":"libdispatch.dylib"},
          {"symbol":"MyApp.a","file":"A.swift","library":"MyApp","owner":"DEVELOPER"},
          {"symbol":"UIKit.x","library":"UIKitCore"},
          {"symbol":"MyApp.b","file":"B.swift","library":"MyApp","owner":"DEVELOPER"}
        ]}]}
        """#)
        let frames = selector.frames(from: event, filter: FrameFilter(appFramesOnly: true))
        #expect(frames.map(\.symbol) == ["MyApp.a", "MyApp.b"])
        #expect(frames.map(\.index) == [2, 4])
        #expect(selector.frames(from: event).map(\.index) == [0, 1, 2, 3, 4])
    }

    @Test("frames carry address and column; no address stays nil")
    func addressAndColumn() throws {
        let event = try event(#"""
        {"threads":[{"crashed":true,"frames":[
          {"symbol":"native","address":"4295000000","column":"3","line":"12"},
          {"symbol":"hex","address":"0x10"},
          {"symbol":"managed","line":"5"}
        ]}]}
        """#)
        let frames = selector.frames(from: event)
        #expect(frames.map(\.address) == [4_295_000_000, 16, nil])
        #expect(frames[0].column == 3)
        #expect(frames[0].line == 12)
    }
}
