import Foundation

enum SourceFileMatcher {
    /// Build products duplicate source that lives elsewhere (SPM checkouts in
    /// .build/DerivedData), never the copy the user wants to edit.
    private static let buildDirectoryComponents: Set<Substring> = [".build", "build", "DerivedData"]

    /// Only components below `cwd` count, so a cwd like ~/build/app is unaffected.
    static func isInBuildDirectory(_ path: String, cwd: String) -> Bool {
        let relative = path.hasPrefix(cwd) ? path.dropFirst(cwd.count) : path[...]
        return relative.split(separator: "/").contains { buildDirectoryComponents.contains($0) }
    }

    static func requiredExtension(of file: String) throws -> String {
        let ext = (file as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else {
            throw InvalidInputError("frame file '\(file)' has no extension — cannot resolve it to a source file.")
        }
        return ext
    }

    /// Exactly one match among `listed`, or an error rather than a guess.
    static func resolve(_ file: String, among listed: [String], cwd: String) throws -> String {
        let allMatches = listed.filter { $0.hasSuffix("/\(file)") }
        let matches = allMatches.filter { !isInBuildDirectory($0, cwd: cwd) }
        switch matches.count {
        case 1:
            return matches[0]
        case 0 where !allMatches.isEmpty:
            throw InvalidInputError(
                "'\(file)' only matches inside build directories under \(cwd) — run from the app's repo root.")
        case 0:
            throw InvalidInputError("found no file named '\(file)' under \(cwd) — run from the app's repo root.")
        default:
            let indentedMatches = matches.map { "  \($0)" }.joined(separator: "\n")
            throw InvalidInputError("'\(file)' is ambiguous under \(cwd):\n" + indentedMatches)
        }
    }

    /// `filesByExtension` holds each extension's listing once, so walking many frames stays cheap.
    static func firstResolvable(
        _ located: [FrameSourceLocation], filesByExtension: [String: [String]], cwd: String
    ) -> FrameSourceLocation? {
        var matchesByName: [String: Int] = [:]
        for paths in filesByExtension.values {
            for path in paths where !isInBuildDirectory(path, cwd: cwd) {
                matchesByName[(path as NSString).lastPathComponent, default: 0] += 1
            }
        }
        return located.first { matchesByName[$0.file] == 1 }
    }
}

struct FrameSourceLocation: Sendable, Equatable {
    var file: String
    var line: Int?
}
