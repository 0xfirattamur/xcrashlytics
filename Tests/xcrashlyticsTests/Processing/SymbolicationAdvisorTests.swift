//
//  SymbolicationAdvisorTests.swift
//  xcrashlytics
//

import Testing
@testable import xcrashlytics

@Suite("symbolication advisor")
struct SymbolicationAdvisorTests {
    @Test("app-owned image detection")
    func appOwned() {
        #expect(SymbolicationAdvisor.isAppOwned(
            BinaryImage(name: "MyApp", uuid: "U1", loadAddress: 0, arch: "arm64", path: "/private/var/containers/Bundle/MyApp.app/MyApp")))
        #expect(!SymbolicationAdvisor.isAppOwned(
            BinaryImage(name: "libsystem", uuid: "U2", loadAddress: 0, arch: "arm64", path: "/usr/lib/libsystem.dylib")))
        #expect(!SymbolicationAdvisor.isAppOwned(
            BinaryImage(name: "UIKit", uuid: "U3", loadAddress: 0, arch: "arm64", path: "/System/Library/UIKit")))
    }
}
