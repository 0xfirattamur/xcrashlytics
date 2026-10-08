import Foundation
import Testing
@testable import xcrashlytics

@Suite("Firebase event metadata")
struct EventMetadataTests {
    @Test("indexes raw domains and userInfo keys")
    func indexesRawMetadata() throws {
        let json = #"""
        {
          "eventId": "E1",
          "error": {
            "domain": "com.metrickit.diagnostics.cpu",
            "userInfo": {
              "reason": "cpu spike",
              "diagnosis": "main-thread hang",
              "top_frames": "BlurDetectionService.analyzeBlur"
            }
          }
        }
        """#
        let event = CrashlyticsEvent(eventId: "E1", rawJSON: json)
        let metadata = CrashlyticsEventMetadataReader(event)

        #expect(metadata.matches("com.metrickit.diagnostics.cpu"))
        #expect(metadata.matchesDomain("com.metrickit.diagnostics"))
        #expect(metadata.matchesUserInfoFilter("reason=cpu spike"))
        #expect(metadata.matchesUserInfoFilter("top_frames"))
        #expect(!metadata.matchesUserInfoFilter("reason=oom"))
    }

    private func metadata(_ json: String, subtitle: String? = nil) -> CrashlyticsEventMetadataReader {
        CrashlyticsEventMetadataReader(CrashlyticsEvent(eventId: "E1", issueSubtitle: subtitle, rawJSON: json))
    }

    @Test("--user-info-key matches Crashlytics customKeys (a map)")
    func customKeysMap() {
        let metadata = metadata(#"{"customKeys":{"environment":"Release","nserror-code":"0","level":"vip"}}"#)
        #expect(metadata.matchesUserInfoFilter("environment=release"))
        #expect(metadata.matchesUserInfoFilter("LEVEL"))
        #expect(metadata.matchesUserInfoFilter("nserror-code=0"))
        #expect(!metadata.matchesUserInfoFilter("environment=debug"))
        #expect(!metadata.matchesUserInfoFilter("missing"))
    }

    @Test("--user-info-key also reads customKeys given as a list of key/value pairs")
    func customKeysList() {
        let metadata = metadata(#"{"customKeys":[{"key":"plan","value":"pro"},{"key":"seats","value":3}]}"#)
        #expect(metadata.matchesUserInfoFilter("plan=pro"))
        #expect(metadata.matchesUserInfoFilter("seats=3"))
        #expect(!metadata.matchesUserInfoFilter("plan=free"))
    }

    @Test("--domain matches domain fields and the issue subtitle, not arbitrary values")
    func domainMatching() {
        let json = #"""
        {
          "customKeys": {"nserror-domain": "com.apple.CoreML", "note": "com.unrelated.value"},
          "errors": [{"subtitle": "Domain: com.apple.Vision\nCode: 9"}],
          "breadcrumbs": [{"title": "opened com.breadcrumb.screen"}]
        }
        """#
        let metadata = metadata(json, subtitle: "com.metrickit.diagnostics.cpu (1) - spike")
        #expect(metadata.matchesDomain("com.apple.CoreML"))
        #expect(metadata.matchesDomain("com.apple.vision"))
        #expect(metadata.matchesDomain("com.metrickit.diagnostics"))
        #expect(!metadata.matchesDomain("com.unrelated.value"))
        #expect(!metadata.matchesDomain("com.breadcrumb.screen"))
        #expect(metadata.matches("com.breadcrumb.screen"))
    }
}
