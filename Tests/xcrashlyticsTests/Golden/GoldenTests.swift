import Foundation
import Testing

/// One golden case: a command line and the world it runs in.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    let name: String
    let arguments: [String]
    let world: GoldenWorld

    init(_ name: String, _ arguments: [String], world: GoldenWorld = GoldenWorld()) {
        self.name = name
        self.arguments = arguments
        self.world = world
    }

    var testDescription: String { name }
}

/// Byte-exact external behavior: every case's output is compared byte for byte against its recorded golden.
///
/// Record with `XCRASHLYTICS_RECORD_GOLDENS=1 swift test --filter Golden`. Without it every
/// case is compared byte for byte against `Golden/Fixtures/<name>.golden`.
@Suite("golden outputs")
struct GoldenTests {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let recording = ProcessInfo.processInfo.environment["XCRASHLYTICS_RECORD_GOLDENS"] == "1"

    @Test("case names are unique file names", .enabled(if: !GoldenTests.recording))
    func uniqueNames() {
        let names = GoldenCases.all.map(\.name)
        #expect(Set(names).count == names.count, "duplicate golden case names")
        #expect(names.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }, "names are lowercase-dash words")
    }

    @Test("command output matches its golden", arguments: GoldenCases.all)
    func matchesGolden(_ golden: GoldenCase) async throws {
        let first = await GoldenHarness.run(golden.arguments, world: golden.world)
        let url = Self.directory.appendingPathComponent("\(golden.name).golden")
        if Self.recording {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try Data(first.serialized.utf8).write(to: url, options: .atomic)
            return
        }
        let second = await GoldenHarness.run(golden.arguments, world: golden.world)
        #expect(first == second, "\(golden.name): two runs produced different output")
        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("\(golden.name): missing golden file; record with XCRASHLYTICS_RECORD_GOLDENS=1")
            return
        }
        if first.serialized != expected {
            Issue.record("\(golden.name) differs from its golden:\n\(Self.diff(expected: expected, actual: first.serialized))")
        }
    }

    /// The first differing lines, each side prefixed `-` (golden) and `+` (actual), with one line of context.
    static func diff(expected: String, actual: String, limit: Int = 6) -> String {
        let old = expected.components(separatedBy: "\n")
        let new = actual.components(separatedBy: "\n")
        var lines: [String] = []
        var differing = 0
        for index in 0..<max(old.count, new.count) {
            let left = index < old.count ? old[index] : nil
            let right = index < new.count ? new[index] : nil
            if left == right { continue }
            if differing == 0, index > 0 { lines.append("  \(index): \(old[index - 1])") }
            if let left { lines.append("- \(index + 1): \(left)") }
            if let right { lines.append("+ \(index + 1): \(right)") }
            differing += 1
            if differing == limit { lines.append("… more differences"); break }
        }
        return lines.joined(separator: "\n")
    }
}
