import Testing
@testable import xcrashlytics

@Suite("version criteria")
struct VersionCriteriaTests {
    @Test("an empty criteria admits everything, including a missing version")
    func empty() {
        let criteria = VersionCriteria()
        #expect(criteria.isEmpty)
        #expect(criteria.admits(nil))
        #expect(criteria.admits("anything"))
    }

    @Test("--app-version matches the same release; unparseable values compare as text")
    func appVersion() {
        let criteria = VersionCriteria(appVersion: "6.16.0")
        #expect(criteria.admits("6.16.0 (937)"))
        #expect(criteria.admits("6.16"))
        #expect(!criteria.admits("6.16.1"))
        #expect(!criteria.admits("1.0-beta"))
        #expect(!criteria.admits(nil))
        #expect(VersionCriteria(appVersion: "nightly").admits("Nightly"))
    }

    @Test("--since-version is a lower bound; unparseable values never pass")
    func sinceVersion() {
        let criteria = VersionCriteria(sinceVersion: "6.16.0")
        #expect(criteria.admits("6.16.0"))
        #expect(criteria.admits("7.0"))
        #expect(!criteria.admits("6.9.0"))
        #expect(!criteria.admits("abc"))
        #expect(!criteria.admits(nil))
        #expect(!VersionCriteria(sinceVersion: "abc").admits("2.0"))
        #expect(!VersionCriteria(sinceVersion: "1.0").admits("1.0-beta"))
    }

    @Test("both selections must hold, each against its own text")
    func combined() {
        let criteria = VersionCriteria(appVersion: "6.16.0 (937)", sinceVersion: "6.10")
        #expect(criteria.admits("6.16.0 (937)", release: "6.16.0"))
        #expect(!criteria.admits("6.16.0 (938)", release: "6.16.0"))
        #expect(!criteria.admits("6.16.0 (937)", release: "6.9.0"))
    }
}
