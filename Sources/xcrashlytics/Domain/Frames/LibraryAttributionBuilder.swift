import Foundation

struct LibraryAttributionBuilder: Sendable {
    let selector: FrameSelector

    static let limit = 10

    func attribution(for events: [CrashlyticsEvent]) -> LibraryAttribution? {
        guard !events.isEmpty else { return nil }
        var dominant = Tally()
        var blamed = Tally()
        for event in events {
            let crashed = selector.stackFrames(from: event, crashingThreadOnly: false)
                .filter { !selector.classifier.isSystemFrame($0) }
            var seen = Set<String>()
            for frame in crashed {
                guard let library = FrameClassifier.knownLibrary(frame.library),
                      seen.insert(library).inserted else { continue }
                dominant.add(library, owner: frame.owner)
            }
            if let frame = event.blameFrame, let library = FrameClassifier.knownLibrary(frame.library) {
                blamed.add(library, owner: frame.owner)
            }
        }
        return LibraryAttribution(
            dominantLibraries: dominant.entries(of: events.count),
            blameLibraries: blamed.entries(of: events.count))
    }

    private struct Tally {
        private var counts: [String: Int] = [:]
        private var owners: [String: [String: Int]] = [:]

        mutating func add(_ library: String, owner: String?) {
            counts[library, default: 0] += 1
            if let owner = owner?.trimmedNonEmpty { owners[library, default: [:]][owner, default: 0] += 1 }
        }

        func entries(of total: Int) -> [LibraryAttribution.Entry] {
            counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(LibraryAttributionBuilder.limit)
                .map { library, count in
                    LibraryAttribution.Entry(
                        library: library, events: count,
                        share: (Double(count) / Double(total) * 1000).rounded() / 1000,
                        owner: dominantOwner(of: library))
                }
        }

        /// The most frequent owner; ties go to the alphabetically first.
        private func dominantOwner(of library: String) -> String? {
            owners[library]?.max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            }?.key
        }
    }
}
