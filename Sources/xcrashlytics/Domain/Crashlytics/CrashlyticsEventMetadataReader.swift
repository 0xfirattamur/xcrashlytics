import Foundation

/// Searchable metadata of one event, built from its typed fields and raw JSON: free text,
/// error domain, and developer-supplied `customKeys`/`userInfo` pairs.
struct CrashlyticsEventMetadataReader: Sendable {
    private let searchText: String
    private let domainTexts: [String]
    private let userInfo: [String: [String]]

    init(_ event: CrashlyticsEvent) {
        var collected = Collected(strings: Self.typedTexts(of: event), domains: Self.typedDomains(of: event))
        if let rawObject = Self.parsedRawJSON(of: event) {
            Self.walk(rawObject, into: &collected)
        }
        self.searchText = collected.strings.joined(separator: "\n")
        self.domainTexts = collected.domains
        self.userInfo = collected.userInfo
    }

    func matches(_ term: String) -> Bool {
        Self.contains(searchText, term)
    }

    func matchesDomain(_ domain: String) -> Bool {
        guard domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return true }
        return domainTexts.contains { Self.contains($0, domain) }
    }

    func matchesUserInfoFilter(_ filter: String) -> Bool {
        let parts = filter.split(separator: "=", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return false }
        let key = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard let values = valueList(for: key) else { return false }
        guard parts.count == 2 else { return true }
        let expected = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return values.contains { Self.contains($0, expected) }
    }

    private func valueList(for key: String) -> [String]? {
        let matching = userInfo.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        return matching.isEmpty ? nil : matching.values.flatMap { $0 }
    }

    private static func contains(_ text: String, _ term: String) -> Bool {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private struct Collected {
        var strings: [String]
        var domains: [String]
        var userInfo: [String: [String]] = [:]
    }

    private static func typedTexts(of event: CrashlyticsEvent) -> [String] {
        [
            event.issueTitle,
            event.issueSubtitle,
            event.processState,
            event.bundleOrPackage,
            event.platform,
        ].compactMap { $0 }
    }

    private static func typedDomains(of event: CrashlyticsEvent) -> [String] {
        var domains = [event.issueSubtitle].compactMap { $0 }
        for entry in event.errors + event.exceptions {
            domains.append(contentsOf: [entry.type, entry.subtitle].compactMap { $0 })
        }
        return domains
    }

    private static func parsedRawJSON(of event: CrashlyticsEvent) -> Any? {
        guard let data = event.rawJSON?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func walk(_ value: Any, into collected: inout Collected) {
        if let dictionary = value as? [String: Any] {
            for (key, value) in dictionary {
                collected.strings.append(key)
                let lowered = key.lowercased()
                if lowered == "userinfo", let userInfoObject = value as? [String: Any] {
                    collect(userInfoObject, into: &collected.userInfo)
                } else if lowered == "customkeys" {
                    collectCustomKeys(value, into: &collected.userInfo)
                }
                collectDomains(key: lowered, value: value, into: &collected.domains)
                walk(value, into: &collected)
            }
        } else if let array = value as? [Any] {
            for element in array {
                walk(element, into: &collected)
            }
        } else if let string = value as? String {
            collected.strings.append(string)
        } else if let number = value as? NSNumber {
            collected.strings.append(number.stringValue)
        }
    }

    // Crashlytics quirk: domains hide in any `…domain…` key and in the type/subtitle
    // of `errors[]`/`exceptions[]`.
    private static func collectDomains(key: String, value: Any, into domains: inout [String]) {
        if key.contains("domain"), let string = value as? String {
            domains.append(string)
        }
        if key == "errors" || key == "exceptions", let entries = value as? [[String: Any]] {
            for entry in entries {
                domains.append(contentsOf: ["type", "subtitle"].compactMap { entry[$0] as? String })
            }
        }
    }

    private static func collect(_ dictionary: [String: Any], into userInfo: inout [String: [String]]) {
        for (key, value) in dictionary {
            userInfo[key, default: []].append(contentsOf: flattenedValues(value))
        }
    }

    // `customKeys` is a `{key: value}` map; a `[{key, value}]` list is accepted too.
    private static func collectCustomKeys(_ value: Any, into userInfo: inout [String: [String]]) {
        if let map = value as? [String: Any] {
            collect(map, into: &userInfo)
        } else if let list = value as? [[String: Any]] {
            for entry in list {
                guard let key = entry["key"] as? String else { continue }
                userInfo[key, default: []].append(contentsOf: flattenedValues(entry["value"] as Any))
            }
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
