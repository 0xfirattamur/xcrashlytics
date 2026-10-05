//
//  SymbolicationAdvisor.swift
//  xcrashlytics
//

import Foundation

/// Detects local Xcode crashes that probably need dSYMs before their frames
/// are readable, so commands can surface a one-line hint.
enum SymbolicationAdvisor {
    /// A hint naming how many app dSYM UUIDs look missing across the crashes,
    /// or nil when nothing app-owned is unresolved.
    static func hint(for crashes: [XcodeCrash]) -> String? {
        var missingUUIDs: Set<String> = []
        var crashIds: Set<String> = []
        for crash in crashes {
            let missingForCrash = crash.event.binaryImages.filter(isAppOwned)
            guard !missingForCrash.isEmpty else { continue }
            crashIds.insert(crash.event.id)
            missingUUIDs.formUnion(missingForCrash.map(\.uuid))
        }
        guard !missingUUIDs.isEmpty else { return nil }
        return "\(missingUUIDs.count) app dSYM UUID(s) may be needed for \(crashIds.count) Xcode crash(es)."
    }

    static func isAppOwned(_ image: BinaryImage) -> Bool {
        image.path.contains(".app/")
            // Fallback: treat anything outside the OS image dirs as app code — over-inclusive by design; the hint text hedges with "may be needed".
            || (!image.path.hasPrefix("/System/") && !image.path.hasPrefix("/usr/lib/"))
    }
}
