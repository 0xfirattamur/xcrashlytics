import Testing
@testable import xcrashlytics

@Suite("source file matcher")
struct SourceFileMatcherTests {
    private let cwd = "/repo"

    @Test("build directories are excluded and a unique remaining match wins")
    func resolvesUniqueSource() throws {
        let listed = ["/repo/.build/x/A.swift", "/repo/Sources/A.swift"]
        #expect(try SourceFileMatcher.resolve("A.swift", among: listed, cwd: cwd) == "/repo/Sources/A.swift")
    }

    @Test("ambiguous, build-only and missing names are rejected")
    func rejectsGuesses() {
        #expect(throws: InvalidInputError.self) {
            try SourceFileMatcher.resolve("A.swift", among: ["/repo/a/A.swift", "/repo/b/A.swift"], cwd: cwd)
        }
        #expect(throws: InvalidInputError.self) {
            try SourceFileMatcher.resolve("A.swift", among: ["/repo/build/A.swift"], cwd: cwd)
        }
        #expect(throws: InvalidInputError.self) { try SourceFileMatcher.resolve("A.swift", among: [], cwd: cwd) }
        #expect(throws: InvalidInputError.self) { try SourceFileMatcher.requiredExtension(of: "Makefile") }
    }

    @Test("the first frame that resolves to exactly one non-build file is chosen")
    func firstResolvable() {
        let located = [FrameSourceLocation(file: "Sdk.m", line: 1), FrameSourceLocation(file: "App.swift", line: 2)]
        let files = ["swift": ["/repo/App.swift"], "m": ["/repo/build/Sdk.m"]]
        #expect(SourceFileMatcher.firstResolvable(located, filesByExtension: files, cwd: cwd)?.file == "App.swift")
    }
}
