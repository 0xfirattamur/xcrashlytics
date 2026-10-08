import Foundation

struct BlameAggregator: Sendable {
    var top: Int
    var windowStart: Date
    /// Its classifier knows the profile's first-party libraries.
    var frameSelector: FrameSelector

    func aggregate(_ samples: [(issue: CrashIssue, events: [CrashlyticsEvent])]) -> BlameAggregation {
        var buckets: [BlameKey: BlameBucket] = [:]
        var counted = 0
        for sample in samples {
            counted += add(events: sample.events, issue: sample.issue, to: &buckets)
        }
        let rows = buckets.values
            .map(Self.summary)
            .sorted(by: Self.ranksBefore)
            .prefix(max(1, top))
        return BlameAggregation(rows: Array(rows), sampledEvents: counted)
    }

    /// Most events, then most users, then a total order over the frame so ties
    /// never depend on dictionary iteration order.
    static func ranksBefore(_ lhs: BlameSummary, _ rhs: BlameSummary) -> Bool {
        if lhs.eventCount != rhs.eventCount { return lhs.eventCount > rhs.eventCount }
        if lhs.users != rhs.users { return lhs.users > rhs.users }
        if lhs.file != rhs.file { return (lhs.file ?? "") < (rhs.file ?? "") }
        if lhs.symbol != rhs.symbol { return (lhs.symbol ?? "") < (rhs.symbol ?? "") }
        if lhs.line != rhs.line { return (lhs.line ?? -1) < (rhs.line ?? -1) }
        if lhs.binaryName != rhs.binaryName { return (lhs.binaryName ?? "") < (rhs.binaryName ?? "") }
        return lhs.exampleIssueId < rhs.exampleIssueId
    }

    private static func summary(_ bucket: BlameBucket) -> BlameSummary {
        BlameSummary(
            file: bucket.key.file,
            line: bucket.key.line,
            symbol: bucket.key.symbol,
            binaryName: bucket.key.binaryName,
            eventCount: bucket.eventCount,
            users: bucket.userHashes.count,
            exampleIssueId: bucket.exampleIssueId ?? "unknown",
            exampleEventId: bucket.exampleEventId,
            topIssueIds: bucket.issueEventCounts
                .sorted {
                    if $0.value != $1.value { return $0.value > $1.value }
                    return $0.key < $1.key
                }
                .prefix(10)
                .map(\.key))
    }

    private func add(
        events: [CrashlyticsEvent],
        issue: CrashIssue,
        to buckets: inout [BlameKey: BlameBucket]
    ) -> Int {
        var added = 0
        for event in events where EventTimestampParser.isIncluded(event: event, onOrAfter: windowStart) {
            guard let frame = frameSelector.blamedFrame(from: event) else { continue }
            added += 1
            let key = BlameKey(frame: frame)
            var bucket = buckets[key] ?? BlameBucket(key: key)
            bucket.eventCount += 1
            if let userId = event.userId {
                bucket.userHashes.insert(SHA256Hasher.hexDigest(of: userId))
            }
            bucket.issueEventCounts[issue.id, default: 0] += 1
            bucket.exampleIssueId = bucket.exampleIssueId ?? issue.id
            bucket.exampleEventId = bucket.exampleEventId
                ?? CrashlyticsIdFormatter.canonicalEventId(event, issueId: issue.id)
            buckets[key] = bucket
        }
        return added
    }
}

private struct BlameKey: Hashable {
    var file: String?
    var line: Int?
    var symbol: String?
    var binaryName: String?

    init(frame: CrashlyticsFrame) {
        self.file = frame.file
        self.line = frame.line
        self.symbol = frame.symbol
        self.binaryName = frame.library
    }
}

private struct BlameBucket {
    var key: BlameKey
    var eventCount: Int = 0
    var userHashes: Set<String> = []
    var issueEventCounts: [String: Int] = [:]
    var exampleIssueId: String?
    var exampleEventId: String?
}
