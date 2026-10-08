import Foundation

enum IssueIdList {
    static func parse(_ rawValues: [String?]) throws -> [String] {
        let ids = rawValues.compactMap { $0 }
            .flatMap { value in value.split(separator: ",").compactMap { String($0).trimmedNonEmpty } }
            .map(CrashlyticsIdFormatter.canonicalIssueId)
        guard !ids.isEmpty else {
            throw InvalidInputError("provide an issue id argument or --issues FB-a,FB-b.")
        }
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
