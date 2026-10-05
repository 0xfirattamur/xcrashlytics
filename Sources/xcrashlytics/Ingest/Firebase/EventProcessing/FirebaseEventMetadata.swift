import Foundation

struct FirebaseEventMetadata: Sendable {
    private let searchText: String
    private let userInfo: [String: [String]]

    init(_ event: FirebaseEvent) {
        var strings: [String] = [
            event.issueTitle,
            event.issueSubtitle,
            event.processState,
            event.bundleOrPackage,
            event.platform,
        ].compactMap { $0 }
        var userInfo: [String: [String]] = [:]

        if let rawJSON = event.rawJSON,
           let data = rawJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            Self.walk(object, into: &strings, userInfo: &userInfo)
        }

        self.searchText = strings.joined(separator: "\n")
        self.userInfo = userInfo
    }

    func matches(_ term: String) -> Bool {
        contains(searchText, term)
    }

    func matchesDomain(_ domain: String) -> Bool {
        matches(domain)
    }

    func matchesUserInfoFilter(_ filter: String) -> Bool {
        let parts = filter.split(separator: "=", maxSplits: 1).map(String.init)
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard let values = valueList(for: key) else { return false }
        guard parts.count == 2 else { return true }
        let expected = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return values.contains { contains($0, expected) }
    }

    private func valueList(for key: String) -> [String]? {
        userInfo.first { existing, _ in
            existing.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    private func contains(_ text: String, _ term: String) -> Bool {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func walk(_ value: Any, into strings: inout [String], userInfo: inout [String: [String]]) {
        if let dictionary = value as? [String: Any] {
            for (key, value) in dictionary {
                strings.append(key)
                if key.caseInsensitiveCompare("userInfo") == .orderedSame,
                   let info = value as? [String: Any] {
                    collectUserInfo(info, into: &strings, userInfo: &userInfo)
                }
                walk(value, into: &strings, userInfo: &userInfo)
            }
        } else if let array = value as? [Any] {
            for item in array {
                walk(item, into: &strings, userInfo: &userInfo)
            }
        } else if let string = value as? String {
            strings.append(string)
        } else if let number = value as? NSNumber {
            strings.append(number.stringValue)
        }
    }

    private static func collectUserInfo(
        _ dictionary: [String: Any],
        into strings: inout [String],
        userInfo: inout [String: [String]]
    ) {
        for (key, value) in dictionary {
            strings.append(key)
            let values = flattenedValues(value)
            userInfo[key, default: []].append(contentsOf: values)
            strings.append(contentsOf: values)
        }
    }

    private static func flattenedValues(_ value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let number = value as? NSNumber { return [number.stringValue] }
        if let array = value as? [Any] { return array.flatMap(flattenedValues) }
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, value in [key] + flattenedValues(value) }
        }
        return []
    }
}
