//
//  EventMetadataTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

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
        let event = FirebaseEvent(eventId: "E1", rawJSON: json)
        let metadata = FirebaseEventMetadata(event)

        #expect(metadata.matches("com.metrickit.diagnostics.cpu"))
        #expect(metadata.matchesDomain("com.metrickit.diagnostics"))
        #expect(metadata.matchesUserInfoFilter("reason=cpu spike"))
        #expect(metadata.matchesUserInfoFilter("top_frames"))
        #expect(!metadata.matchesUserInfoFilter("reason=oom"))
    }
}
