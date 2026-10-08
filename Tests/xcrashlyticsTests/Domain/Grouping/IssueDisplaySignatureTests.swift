import Testing
@testable import xcrashlytics

@Suite("display signature")
struct IssueDisplaySignatureTests {
    private func signature(_ title: String?) -> IssueDisplaySignature? {
        IssueDisplaySignature(CrashIssue(providerId: "I1", title: title, exceptionType: "FATAL"))
    }

    @Test("a non-fatal title at the Crashlytics SDK frame names no file or symbol, only the module")
    func crashlyticsSDKTitle() throws {
        let value = try #require(signature(
            "[Core] FIRCLSNonFatalError.m - -[FIRCLSNonFatalError initWithError:userInfo:rolloutsInfoJSON:]"))
        #expect(value.module == "Core")
        #expect(value.file == nil)
        #expect(value.symbol == nil)
    }

    @Test("a module-only title has an empty symbol and no file; missing or blank titles have no signature")
    func degenerate() throws {
        let moduleOnly = try #require(signature("[Core]"))
        #expect(moduleOnly.module == "Core")
        #expect(moduleOnly.file == nil)
        #expect(signature(nil) == nil)
        #expect(signature("   ") == nil)
    }
}
