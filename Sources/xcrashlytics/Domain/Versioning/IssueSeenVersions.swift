// Crashlytics quirk: first/last seen are the versions of the first and most recent event
// (chronological), not range bounds: the last-seen version can be lower than the first.
enum IssueSeenVersions {
    static func description(first: String?, last: String?) -> String? {
        switch (first, last) {
        case let (first?, last?): "first seen \(first) · last seen \(last)"
        case let (first?, nil): "first seen \(first)"
        case let (nil, last?): "last seen \(last)"
        case (nil, nil): nil
        }
    }
}
