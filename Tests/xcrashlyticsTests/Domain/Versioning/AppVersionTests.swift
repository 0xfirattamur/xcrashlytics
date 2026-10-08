import Testing
@testable import xcrashlytics

@Suite("app version")
struct AppVersionTests {
    private func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    @Test("dotted numbers compare numerically and pad missing components with zero")
    func numbers() throws {
        #expect(try version("6.16.0") > version("6.9.0"))
        #expect(try version("6.16") == version("6.16.0"))
        #expect(try version("6.16.0.1") > version("6.16.0"))
        #expect(try version("v2.0") > version("1.9.9"))
    }

    @Test("a pre-release sorts below its release and orders by identifier")
    func prerelease() throws {
        #expect(try version("1.0-beta") < version("1.0"))
        #expect(try version("1.0-beta.2") > version("1.0-beta.1"))
        #expect(try version("1.0-beta.2") < version("1.0-beta.10"))
        #expect(try version("1.0-rc.1") > version("1.0-beta.9"))
        #expect(try version("1.1-alpha") > version("1.0"))
    }

    @Test("build numbers do not affect ordering")
    func builds() throws {
        #expect(try version("6.16.0 (937)") == version("6.16.0"))
        #expect(try version("6.16.0+5") == version("6.16.0 (1)"))
    }

    @Test("same release also requires the build when the expected version names one")
    func sameRelease() throws {
        #expect(try version("6.16.0 (937)").isSameRelease(as: version("6.16.0")))
        #expect(try version("6.16.0 (937)").isSameRelease(as: version("6.16.0 (937)")))
        #expect(try !version("6.16.0 (937)").isSameRelease(as: version("6.16.0 (938)")))
        #expect(try !version("6.16.0").isSameRelease(as: version("6.16.0 (938)")))
    }

    @Test("text that is not a version does not parse")
    func unparseable() {
        for text in ["abc", "", "1..2", "6.x", "1.0.x", "99999999999999999999.1"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }

    @Test("require names the flag and maps to BAD_INPUT")
    func requireVersion() throws {
        _ = try AppVersion.require("6.16.0 (937)", flag: "--app-version")
        #expect(throws: InvalidInputError(
            "--since-version 'abc' is not a version; use dotted numbers such as 6.16.0 or 6.16.0-beta.1.")
        ) {
            _ = try AppVersion.require("abc", flag: "--since-version")
        }
    }
}
