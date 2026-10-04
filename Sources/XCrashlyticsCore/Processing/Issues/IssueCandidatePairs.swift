import Foundation

public struct RelatedIssueGroup: Encodable, Sendable {
    public var issueIds: [String]
    public var reason: String

    public init(issueIds: [String], reason: String) {
        self.issueIds = issueIds
        self.reason = reason
    }
}

/// Groups records directly by signature without materializing every pair.
public enum RelatedIssueGroups {
    public static func build(firebase: [CrashIssue], xcode: [XcodeCrash]) -> [RelatedIssueGroup] {
        let items = firebase.compactMap { issue -> (signature: String, id: String)? in
            guard let signature = CrashSignature.of(issue) else { return nil }
            return (signature.symbol, issue.id)
        } + xcode.compactMap { crash -> (signature: String, id: String)? in
            guard let signature = CrashSignature.of(crash.event) else { return nil }
            return (signature.symbol, crash.event.id)
        }
        let grouped = Dictionary(grouping: items, by: \.signature)
        return grouped.keys.sorted().compactMap { signature in
            let ids = grouped[signature, default: []].map(\.id).sorted()
            guard ids.count > 1 else { return nil }
            return RelatedIssueGroup(issueIds: ids, reason: "same crash signature")
        }
    }
}
