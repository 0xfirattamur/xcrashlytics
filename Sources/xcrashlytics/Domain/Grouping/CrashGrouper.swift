import Foundation

/// Merges Firebase issues and local Xcode crashes that share a culprit symbol into `CrashGroup`s.
struct CrashGrouper: Sendable {
    func group(local: [XcodeCrash], firebase: [CrashIssue]) -> [CrashGroup] {
        var buckets = GroupBuckets()
        for issue in firebase {
            buckets.add(issue, under: groupKey(for: issue))
        }
        for crash in withoutDuplicates(local) {
            buckets.add(crash, under: groupKey(for: crash.event))
        }
        return sortedByImpact(buckets.groups())
    }

    // MARK: - Keys

    fileprivate struct GroupKey {
        let symbol: String
        let module: String?
    }

    /// Crashes with no usable culprit get a unique key so they never merge by accident.
    private func groupKey(for issue: CrashIssue) -> GroupKey {
        if let signature = CrashSignature.of(issue) {
            return GroupKey(symbol: signature.symbol, module: signature.module)
        }
        return GroupKey(symbol: "\(issue.source.rawValue):\(issue.id)", module: nil)
    }

    private func groupKey(for event: CrashEvent) -> GroupKey {
        if let signature = CrashSignature.of(event) {
            return GroupKey(symbol: signature.symbol, module: signature.module)
        }
        return GroupKey(symbol: "\(event.source.rawValue):\(event.id)", module: nil)
    }

    // MARK: - Steps

    /// The Organizer stores the same crash under several filter folders.
    private func withoutDuplicates(_ crashes: [XcodeCrash]) -> [XcodeCrash] {
        var seenEventIds = Set<String>()
        return crashes.filter { seenEventIds.insert($0.event.id).inserted }
    }

    /// Most impactful first: cross-source groups, then event volume, then local repro count.
    private func sortedByImpact(_ groups: [CrashGroup]) -> [CrashGroup] {
        groups.sorted { lhs, rhs in
            if lhs.isCrossSource != rhs.isCrossSource { return lhs.isCrossSource }
            if lhs.totalEvents != rhs.totalEvents { return lhs.totalEvents > rhs.totalEvents }
            if lhs.xcode.count != rhs.xcode.count { return lhs.xcode.count > rhs.xcode.count }
            // Deterministic: `sorted` is not stable, so equal groups order by key.
            return lhs.symbol < rhs.symbol
        }
    }
}

/// Members collected per group key, remembering the order in which keys first appeared.
private struct GroupBuckets {
    private struct Bucket {
        var module: String?
        var firebase: [CrashIssue] = []
        var xcode: [XcodeCrash] = []
    }

    private var bucketsByKey: [String: Bucket] = [:]
    private var keysInFirstSeenOrder: [String] = []

    mutating func add(_ issue: CrashIssue, under key: CrashGrouper.GroupKey) {
        registerKey(key)
        bucketsByKey[key.symbol, default: Bucket(module: key.module)].firebase.append(issue)
    }

    mutating func add(_ crash: XcodeCrash, under key: CrashGrouper.GroupKey) {
        registerKey(key)
        bucketsByKey[key.symbol, default: Bucket(module: key.module)].xcode.append(crash)
        // A Firebase module wins; a local one only fills the gap.
        if bucketsByKey[key.symbol]?.module == nil {
            bucketsByKey[key.symbol]?.module = key.module
        }
    }

    func groups() -> [CrashGroup] {
        keysInFirstSeenOrder.compactMap { symbol in
            bucketsByKey[symbol].map { bucket in
                CrashGroup(
                    symbol: symbol,
                    module: bucket.module,
                    firebase: bucket.firebase,
                    xcode: bucket.xcode
                )
            }
        }
    }

    private mutating func registerKey(_ key: CrashGrouper.GroupKey) {
        if bucketsByKey[key.symbol] == nil { keysInFirstSeenOrder.append(key.symbol) }
    }
}
