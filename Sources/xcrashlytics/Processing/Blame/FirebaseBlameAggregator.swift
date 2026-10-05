import Foundation

struct BlameSummary: Encodable, Sendable {
    var file: String?
    var line: Int?
    var symbol: String?
    var binaryName: String?
    var eventCount: Int
    var users: Int
    var exampleIssueId: String
    var exampleEventId: String?
    var topIssueIds: [String]

    fileprivate init(_ bucket: BlameBucket) {
        self.file = bucket.key.file
        self.line = bucket.key.line
        self.symbol = bucket.key.symbol
        self.binaryName = bucket.key.binaryName
        self.eventCount = bucket.eventCount
        self.users = bucket.userHashes.count
        self.exampleIssueId = bucket.exampleIssueId ?? "unknown"
        self.exampleEventId = bucket.exampleEventId
        self.topIssueIds = bucket.issueEventCounts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(10)
            .map(\.key)
    }
}

struct FirebaseBlameAggregator {
    var firebase: CrashlyticsAPI
    var top: Int
    var cutoff: Date?
    var eventsPerIssue: Int
    var concurrency: Int

    init(
        firebase: CrashlyticsAPI,
        top: Int,
        cutoff: Date?,
        eventsPerIssue: Int,
        concurrency: Int = 6
    ) {
        self.firebase = firebase
        self.top = top
        self.cutoff = cutoff
        self.eventsPerIssue = eventsPerIssue
        self.concurrency = concurrency
    }

    func aggregate(issues: [CrashIssue]) async throws -> [BlameSummary] {
        var buckets: [BlameKey: BlameBucket] = [:]
        let samples = try await IssueEventSampler(
            firebase: firebase, eventsPerIssue: eventsPerIssue, concurrency: concurrency
        ).sample(issues: issues)
        for sample in samples {
            add(events: sample.events, issue: sample.issue, to: &buckets)
        }
        return buckets.values
            .map(BlameSummary.init)
            .sorted {
                if $0.eventCount != $1.eventCount { return $0.eventCount > $1.eventCount }
                if $0.users != $1.users { return $0.users > $1.users }
                return "\($0.file ?? "")\($0.symbol ?? "")" < "\($1.file ?? "")\($1.symbol ?? "")"
            }
            .prefix(max(1, top))
            .map { $0 }
    }

    private func add(
        events: [FirebaseEvent],
        issue: CrashIssue,
        to buckets: inout [BlameKey: BlameBucket]
    ) {
        for event in events where EventDates.isIncluded(event: event, onOrAfter: cutoff) {
            guard let frame = FirebaseEventFrames.blamedFrame(from: event) else { continue }
            let key = BlameKey(frame: frame)
            var bucket = buckets[key] ?? BlameBucket(key: key)
            bucket.eventCount += 1
            if let userId = event.userId {
                bucket.userHashes.insert(Hashing.sha256Hex(userId))
            }
            bucket.issueEventCounts[issue.id, default: 0] += 1
            bucket.exampleIssueId = bucket.exampleIssueId ?? issue.id
            bucket.exampleEventId = bucket.exampleEventId
                ?? FirebaseIdentifiers.canonicalEventId(event, issueId: issue.id)
            buckets[key] = bucket
        }
    }
}

private struct BlameKey: Hashable {
    var file: String?
    var line: Int?
    var symbol: String?
    var binaryName: String?

    init(frame: FirebaseFrame) {
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
