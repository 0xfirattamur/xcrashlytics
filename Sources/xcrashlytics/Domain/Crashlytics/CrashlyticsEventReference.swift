import Foundation

struct CrashlyticsEventReference: Sendable, Equatable {
    var issueId: String
    var eventId: String

    init?(_ id: String) {
        guard CrashlyticsIdFormatter.isCanonicalLike(id), let range = id.range(of: "/events/") else {
            return nil
        }
        self.issueId = String(id[id.index(id.startIndex, offsetBy: 3)..<range.lowerBound])
        self.eventId = String(id[range.upperBound...])
        guard !issueId.isEmpty, !eventId.isEmpty else { return nil }
    }

    // Crashlytics quirk: the event part may be a pasted console `sessionEventKey`, not the API event id.
    func matches(_ event: CrashlyticsEvent) -> Bool {
        let candidates = CrashlyticsIdFormatter.candidateEventIds(forKey: eventId)
        return [event.eventId, event.resourceName].contains { $0.map(candidates.contains) == true }
    }
}
