import Testing
@testable import xcrashlytics

@Suite("issue title")
struct IssueTitleTests {
    @Test("splits module, file and symbol; the last ' - ' separates file from symbol")
    func parts() throws {
        let title = try #require(IssueTitle("[M] A - B.swift - run()"))
        #expect(title.module == "M")
        #expect(title.file == "A - B.swift")
        #expect(title.symbol == "run()")
    }

    @Test("module and file are optional; a bare title is the symbol")
    func bare() throws {
        let title = try #require(IssueTitle("  objectdestroyTm "))
        #expect(title.module == nil)
        #expect(title.file == nil)
        #expect(title.symbol == "objectdestroyTm")
    }

    @Test("missing or blank titles have no parts")
    func blank() {
        #expect(IssueTitle(nil) == nil)
        #expect(IssueTitle("   ") == nil)
    }

    @Test("the Crashlytics SDK's recordError frame is recognized")
    func sdkFrame() throws {
        #expect(try #require(IssueTitle("[Core] FIRCrashlytics.m - -[FIRCrashlytics recordError:]")).namesCrashlyticsSDK)
        #expect(try !#require(IssueTitle("[Core] Checkout.swift - pay()")).namesCrashlyticsSDK)
    }
}
