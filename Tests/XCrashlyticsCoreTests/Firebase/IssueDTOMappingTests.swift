//
//  IssueDTOMappingTests.swift
//  xcrashlyticsTests
//
//  Created by FIRAT TAMUR on 11.06.2026.
//

import Foundation
import Testing
@testable import XCrashlyticsCore

@Suite("issue DTO mapping")
struct IssueDTOMappingTests {
    private func dto(first: String?, last: String?) throws -> FirebaseDTO.IssueDTO {
        var fields = [
            #""id": "I1""#,
            #""title": "Crash in Checkout""#,
            #""errorType": "EXC_BAD_ACCESS""#,
        ]
        if let first { fields.append(#""firstSeenVersion": "\#(first)""#) }
        if let last { fields.append(#""lastSeenVersion": "\#(last)""#) }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(FirebaseDTO.IssueDTO.self, from: Data(json.utf8))
    }

    @Test("carries first- and last-seen versions onto the issue")
    func mapsSeenVersions() throws {
        let record = try dto(first: "6.2.0", last: "6.16.0").toCrashIssue()
        #expect(record.firstSeenVersion == "6.2.0")
        #expect(record.lastSeenVersion == "6.16.0")
        #expect(record.bundleVersion == "6.16.0")
    }

    @Test("falls back to first-seen when last-seen is missing")
    func fallsBackToFirstSeen() throws {
        let record = try dto(first: "6.2.0", last: nil).toCrashIssue()
        #expect(record.firstSeenVersion == "6.2.0")
        #expect(record.lastSeenVersion == nil)
        #expect(record.bundleVersion == "6.2.0")
    }
}
