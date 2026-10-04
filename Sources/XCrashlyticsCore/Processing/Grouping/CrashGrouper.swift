//
//  CrashGrouper.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation

/// Clusters crashes from both sources into `CrashGroup`s by their
/// `CrashSignature`, so one root cause shows as one group regardless of how
/// Firebase split it or how many times it reproduced locally.
public struct CrashGrouper: Sendable {
    public init() {}

    public func group(local: [XcodeCrash], firebase: [CrashIssue]) -> [CrashGroup] {
        // De-duplicate local crashes by incident id — the Organizer stores the
        // same crash under several filter folders.
        var seen = Set<String>()
        let dedupedLocal = local.filter { seen.insert($0.event.id).inserted }

        // Bucket by signature symbol. Crashes with no usable culprit get a
        // unique key so they stay separate rather than merging by accident.
        var firebaseByKey: [String: [CrashIssue]] = [:]
        var localByKey: [String: [XcodeCrash]] = [:]
        var moduleByKey: [String: String?] = [:]
        var order: [String] = []

        func key(for issue: CrashIssue) -> (key: String, module: String?) {
            if let sig = CrashSignature.of(issue) {
                return (sig.symbol, sig.module)
            }
            return ("\(issue.source.rawValue):\(issue.id)", nil)
        }
        func key(for event: CrashEvent) -> (key: String, module: String?) {
            if let sig = CrashSignature.of(event) {
                return (sig.symbol, sig.module)
            }
            return ("\(event.source.rawValue):\(event.id)", nil)
        }

        for event in firebase {
            let (k, module) = key(for: event)
            if firebaseByKey[k] == nil && localByKey[k] == nil { order.append(k) }
            firebaseByKey[k, default: []].append(event)
            moduleByKey[k] = moduleByKey[k] ?? module
        }
        for crash in dedupedLocal {
            let (k, module) = key(for: crash.event)
            if firebaseByKey[k] == nil && localByKey[k] == nil { order.append(k) }
            localByKey[k, default: []].append(crash)
            if moduleByKey[k] == nil || moduleByKey[k] == .some(nil) { moduleByKey[k] = module }
        }

        let groups = order.map { k in
            CrashGroup(
                symbol: k,
                module: moduleByKey[k] ?? nil,
                firebase: firebaseByKey[k] ?? [],
                xcode: localByKey[k] ?? []
            )
        }

        // Most impactful first: cross-source groups, then by event volume.
        return groups.sorted { lhs, rhs in
            if lhs.isCrossSource != rhs.isCrossSource { return lhs.isCrossSource }
            if lhs.totalEvents != rhs.totalEvents { return lhs.totalEvents > rhs.totalEvents }
            return lhs.xcode.count > rhs.xcode.count
        }
    }
}
