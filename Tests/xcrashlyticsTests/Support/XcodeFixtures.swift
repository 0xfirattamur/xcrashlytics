import Foundation
import Testing

/// Reads files from the test bundle's `Fixtures` directory.
enum XcodeFixtures {
    static func text(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
