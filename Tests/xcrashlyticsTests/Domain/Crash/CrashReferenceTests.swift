import Testing
@testable import xcrashlytics

@Suite("crash reference")
struct CrashReferenceTests {
    private let link = "https://console.firebase.google.com/project/p/crashlytics/app/ios:com.x.app/issues/I1?sessionEventKey=s_e1"

    @Test("any-crash grammar: XC, FB, FB event, and console link")
    func anyCrash() throws {
        #expect(try CrashReference.parse("XC-AAAA", expecting: .anyCrash) == .xcodeCrash(id: "XC-AAAA"))
        #expect(try CrashReference.parse("FB-I1", expecting: .anyCrash) == .firebaseIssue(issueId: "I1"))
        let event = try CrashReference.parse("FB-I1/events/E1", expecting: .anyCrash)
        #expect(event == .firebaseEvent(try #require(CrashlyticsEventReference("FB-I1/events/E1"))))
        let parsed = try CrashReference.parse(link, expecting: .anyCrash)
        #expect(parsed == .consoleLink(try FirebaseConsoleLink(link)))
    }

    @Test("a lowercase FB- prefix is rejected where the id must be exact")
    func lowercasePrefix() {
        #expect(throws: InvalidInputError("id must be XC-<uuid>, FB-<id>, or a Firebase console link; got 'fb-I1'.")) {
            _ = try CrashReference.parse("fb-I1", expecting: .anyCrash)
        }
        #expect(throws: InvalidInputError("id must start with FB- or XC-; got 'fb-I1'.")) {
            _ = try CrashReference.parse("fb-I1", expecting: .openable)
        }
    }

    @Test("issue-level grammar accepts any-case FB- and rejects Xcode ids with its own message")
    func firebaseIssueOnly() throws {
        #expect(try CrashReference.parse("fb-I1", expecting: .firebaseIssue) == .firebaseIssue(issueId: "I1"))
        let message = "issue must be FB-<id>, FB-<id>/events/<event>, or a Firebase console link; got 'XC-AAAA'."
        #expect(throws: InvalidInputError(message)) {
            _ = try CrashReference.parse("XC-AAAA", expecting: .firebaseIssue)
        }
    }

    @Test("open grammar takes FB and XC ids only, never links")
    func openable() throws {
        #expect(try CrashReference.parse("FB-I1", expecting: .openable) == .firebaseIssue(issueId: "I1"))
        #expect(try CrashReference.parse("XC-AAAA", expecting: .openable) == .xcodeCrash(id: "XC-AAAA"))
        #expect(throws: InvalidInputError("id must start with FB- or XC-; got '\(link)'.")) {
            _ = try CrashReference.parse(link, expecting: .openable)
        }
    }

    @Test("a URL that is not a Crashlytics link fails with the link error, not the id error")
    func badLink() {
        #expect(throws: InvalidInputError("only https://console.firebase.google.com Crashlytics links are supported.")) {
            _ = try CrashReference.parse("https://example.com/x", expecting: .anyCrash)
        }
    }

    @Test("an events path with an empty event id is a plain issue id")
    func emptyEventId() throws {
        #expect(try CrashReference.parse("FB-I1/events/", expecting: .anyCrash) == .firebaseIssue(issueId: "I1/events/"))
    }
}
