import Foundation

enum CrashReference: Equatable, Sendable {
    case firebaseIssue(issueId: String)
    case firebaseEvent(CrashlyticsEventReference)
    case xcodeCrash(id: String)
    case consoleLink(FirebaseConsoleLink)

    /// Each case carries the error wording for input outside it, since commands name different shapes.
    enum Expectation: Sendable {
        /// `show`/`export`: any crash.
        case anyCrash
        /// `breakdown`/`show`/`export` issue-level lookups: Crashlytics only.
        case firebaseIssue
        /// `open`: `FB-` or `XC-` ids, matched case-sensitively; no links.
        case openable

        fileprivate func unsupported(_ raw: String) -> InvalidInputError {
            switch self {
            case .anyCrash:
                InvalidInputError("id must be XC-<uuid>, FB-<id>, or a Firebase console link; got '\(raw)'.")
            case .firebaseIssue:
                InvalidInputError(
                    "issue must be FB-<id>, FB-<id>/events/<event>, or a Firebase console link; got '\(raw)'.")
            case .openable:
                InvalidInputError("id must start with FB- or XC-; got '\(raw)'.")
            }
        }
    }

    static func parse(_ raw: String, expecting expectation: Expectation) throws -> CrashReference {
        let reference: CrashReference? = switch expectation {
        case .anyCrash: try parseAnyCrash(raw)
        case .firebaseIssue: try parseFirebaseIssue(raw)
        case .openable: parseOpenable(raw)
        }
        guard let reference else { throw expectation.unsupported(raw) }
        return reference
    }

    private static func parseAnyCrash(_ raw: String) throws -> CrashReference? {
        if FirebaseConsoleLink.looksLikeURL(raw) { return .consoleLink(try FirebaseConsoleLink(raw)) }
        if raw.hasPrefix("XC-") { return .xcodeCrash(id: raw) }
        if let event = CrashlyticsEventReference(raw) { return .firebaseEvent(event) }
        return raw.hasPrefix("FB-") ? .firebaseIssue(issueId: CrashlyticsIdFormatter.issueId(from: raw)) : nil
    }

    private static func parseFirebaseIssue(_ raw: String) throws -> CrashReference? {
        if FirebaseConsoleLink.looksLikeURL(raw) { return .consoleLink(try FirebaseConsoleLink(raw)) }
        if let event = CrashlyticsEventReference(raw) { return .firebaseEvent(event) }
        return CrashlyticsIdFormatter.isCanonicalLike(raw)
            ? .firebaseIssue(issueId: CrashlyticsIdFormatter.issueId(from: raw)) : nil
    }

    private static func parseOpenable(_ raw: String) -> CrashReference? {
        if raw.hasPrefix("XC-") { return .xcodeCrash(id: raw) }
        guard raw.hasPrefix("FB-") else { return nil }
        if let event = CrashlyticsEventReference(raw) { return .firebaseEvent(event) }
        return .firebaseIssue(issueId: CrashlyticsIdFormatter.issueId(from: raw))
    }
}
