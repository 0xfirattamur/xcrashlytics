import Foundation
import Testing
@testable import xcrashlytics

@Suite("FrameNormalizer")
struct FrameNormalizerTests {
    @Test("lowercases binary + symbol and strips offset")
    func basic() throws {
        let frame = Frame(index: 0, binaryName: "MyApp", symbol: "-[ViewController crashNow] + 24", address: 1)
        let token = try #require(FrameNormalizer.normalize(frame))
        #expect(token.binary == "myapp")
        #expect(token.symbol == "-[viewcontroller crashnow]")
    }

    @Test("strips [unsymbolicated] suffix")
    func unsymStrip() throws {
        let frame = Frame(index: 0, binaryName: "MyApp [unsymbolicated]", address: 1)
        let token = try #require(FrameNormalizer.normalize(frame))
        #expect(token.binary == "myapp")
    }

    @Test("collapses 0x load-address symbols to empty")
    func addressSymbolCollapsed() throws {
        let frame = Frame(index: 0, binaryName: "App", symbol: "0x000000018abc1234 + 40", address: 1)
        let token = try #require(FrameNormalizer.normalize(frame))
        #expect(token.symbol == "")
        #expect(token.binary == "app")
    }

    @Test("collapses long bare hex blobs but keeps short hex-like symbols")
    func hexHeuristic() throws {
        let blob = try #require(FrameNormalizer.normalize(Frame(index: 0, binaryName: "App", symbol: "deadbeefcafe", address: 1)))
        #expect(blob.symbol == "")
        let real = try #require(FrameNormalizer.normalize(Frame(index: 0, binaryName: "App", symbol: "cafe", address: 1)))
        #expect(real.symbol == "cafe")
    }

    @Test("two unsymbolicated frames in the same binary normalize equal")
    func unsymFramesMatch() throws {
        let a = try #require(FrameNormalizer.normalize(Frame(index: 0, binaryName: "App", symbol: "0xdead0000", address: 1)))
        let b = try #require(FrameNormalizer.normalize(Frame(index: 0, binaryName: "App", symbol: "0xbeef1111", address: 2)))
        #expect(a == b)
    }

    @Test("drops abort/threading preamble so app frames enter the compared window")
    func dropsNoiseFrames() {
        let frames = [
            Frame(index: 0, binaryName: "libsystem_kernel.dylib", symbol: "__pthread_kill", address: 0),
            Frame(index: 1, binaryName: "libswift_Concurrency.dylib", symbol: "abort", address: 0),
            Frame(index: 2, binaryName: "MyApp", symbol: "-[VC crash]", address: 0)
        ]
        // topN=1: after dropping the two noise frames, the app frame is the one left.
        let tokens = FrameNormalizer.normalize(frames, topN: 1)
        #expect(tokens.count == 1)
        #expect(tokens.first?.binary == "myapp")
        #expect(tokens.first?.symbol == "-[vc crash]")
    }

    @Test("an all-noise stack falls back to the unfiltered frames")
    func allNoiseFallback() {
        let frames = [
            Frame(index: 0, binaryName: "libsystem_kernel.dylib", symbol: "__pthread_kill", address: 0),
            Frame(index: 1, binaryName: "libdispatch.dylib", symbol: "_dispatch_main", address: 0)
        ]
        let tokens = FrameNormalizer.normalize(frames, topN: 5)
        #expect(tokens.count == 2)
    }

    @Test("returns top-N tokens")
    func topN() {
        let frames = (0..<10).map { Frame(index: $0, binaryName: "B\($0)", symbol: "s\($0)", address: 0) }
        let tokens = FrameNormalizer.normalize(frames, topN: 3)
        #expect(tokens.count == 3)
        #expect(tokens.first?.binary == "b0")
    }
}
