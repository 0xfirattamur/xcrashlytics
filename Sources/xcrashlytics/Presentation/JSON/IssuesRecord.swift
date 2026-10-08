import Foundation

enum IssuesRecord: Encodable, Sendable {
    case issue(IssueSummary)
    case xcodeCrash(XcodeIssueSummary)
    case hint(String?, symbolicationHint: String?)

    private enum CodingKeys: String, CodingKey { case kind, hint, symbolicationHint }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .issue(summary):
            try summary.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("issue", forKey: .kind)
        case let .xcodeCrash(summary):
            try summary.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("xcodeCrash", forKey: .kind)
        case let .hint(hint, symbolicationHint):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("hint", forKey: .kind)
            try container.encodeIfPresent(hint, forKey: .hint)
            try container.encodeIfPresent(symbolicationHint, forKey: .symbolicationHint)
        }
    }
}
