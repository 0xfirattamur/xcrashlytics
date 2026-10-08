import Foundation
import Testing
@testable import xcrashlytics

@Suite("FrameNormalizer")
struct FrameNormalizerTests {
    @Test("0x load-address symbols and long bare hex blobs are address-only; short hex-like symbols are not")
    func addressOnly() {
        #expect(FrameNormalizer.isAddressOnly("0x000000018abc1234"))
        #expect(FrameNormalizer.isAddressOnly("0x102f70000"))
        #expect(FrameNormalizer.isAddressOnly("deadbeefcafe"))
        #expect(!FrameNormalizer.isAddressOnly("cafe"))
        #expect(!FrameNormalizer.isAddressOnly("0x"))
        #expect(!FrameNormalizer.isAddressOnly("closure in Foo.bar(flag: 0x1)"))
    }

    @Test("drops abort/threading preamble so app frames come first")
    func dropsNoiseFrames() {
        let frames = [
            StackFrame(index: 0, binaryName: "libsystem_kernel.dylib", symbol: "__pthread_kill", address: 0),
            StackFrame(index: 1, binaryName: "libswift_Concurrency.dylib", symbol: "abort", address: 0),
            StackFrame(index: 2, binaryName: "MyApp", symbol: "-[VC crash]", address: 0)
        ]
        #expect(FrameNormalizer.meaningful(frames).map(\.index) == [2])
    }

    @Test("an all-noise stack falls back to the unfiltered frames")
    func allNoiseFallback() {
        let frames = [
            StackFrame(index: 0, binaryName: "libsystem_kernel.dylib", symbol: "__pthread_kill", address: 0),
            StackFrame(index: 1, binaryName: "libdispatch.dylib", symbol: "_dispatch_main", address: 0)
        ]
        #expect(FrameNormalizer.meaningful(frames).map(\.index) == [0, 1])
    }
}
