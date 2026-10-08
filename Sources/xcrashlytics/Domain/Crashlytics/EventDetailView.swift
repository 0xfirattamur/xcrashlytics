import Foundation

/// The event fields that explain a crash beyond its stack. Everything here is redacted:
/// a user id never leaves this type.
struct EventDetailView: Sendable, Equatable {
    // Crashlytics quirk: Swift stores a `fatalError` message in `crash_info_entry_N` custom keys.
    var crashInfo: [String]?
    /// The line(s) of `crashInfo` naming the failure, else its last line, else for an
    /// NSException crash without crash info `<type>: <message>`.
    var crashMessage: String?
    var exception: ExceptionSummary?
    /// In full detail `customKeys` is always an object and `logs` an array (`{}`/`[]` when
    /// empty); both are absent in the compact form. `customKeys` excludes `crash_info_entry_N`.
    var customKeys: [String: String]?
    var logs: [Log]?
    var crashedThread: CrashedThread?
    var breadcrumbs: [Breadcrumb]?

    struct ExceptionSummary: Sendable, Equatable {
        var type: String?
        var message: String?
    }

    struct Log: Sendable, Equatable {
        var time: String?
        var message: String?
    }

    struct CrashedThread: Sendable, Equatable {
        var title: String?
        var signal: String?
        var signalCode: String?
        var crashAddress: String?
        var queue: String?
    }

    struct Breadcrumb: Sendable, Equatable {
        var time: String?
        var title: String?
        var params: [String: String]?
    }

    static let failureMarkers = ["Fatal error:", "Precondition failed", "Assertion failed"]

    // Breadcrumbs can run to hundreds of entries, so they are opt-in.
    init(_ event: CrashlyticsEvent, includeBreadcrumbs: Bool = false) {
        let redactor = CustomKeyRedactor(userId: event.userId)
        let entries = Self.crashInfoEntries(event.customKeys)
        let redactedEntries = entries.map { redactor.scrub($0.value) }
        crashInfo = redactedEntries.nilIfEmpty
        exception = event.exceptions.first.flatMap {
            let type = $0.type?.trimmedNonEmpty
            let message = $0.exceptionMessage?.trimmedNonEmpty.map(redactor.scrub)
            return type == nil && message == nil ? nil : ExceptionSummary(type: type, message: message)
        }
        crashMessage = Self.crashMessage(from: redactedEntries) ?? exception.flatMap(Self.exceptionMessage)
        let entryKeys = Set(entries.map(\.key))
        customKeys = redactor.customKeys(event.customKeys.filter { !entryKeys.contains($0.key) })
        logs = event.logs.map { Log(time: $0.time, message: $0.message.map(redactor.scrub)) }
        crashedThread = event.threads.first(where: \.crashed).map {
            CrashedThread(
                title: $0.title, signal: $0.signal, signalCode: $0.signalCode,
                crashAddress: $0.crashAddress, queue: $0.queue)
        }
        breadcrumbs = includeBreadcrumbs
            ? event.breadcrumbs.map {
                Breadcrumb(time: $0.time, title: $0.title, params: redactor.customKeys($0.params).nilIfEmpty)
            }.nilIfEmpty
            : nil
    }

    private static func exceptionMessage(_ exception: ExceptionSummary) -> String? {
        switch (exception.type, exception.message) {
        case let (type?, message?): return "\(type): \(message)"
        case let (type?, nil): return type
        case let (nil, message?): return message
        case (nil, nil): return nil
        }
    }

    private static func crashInfoEntries(_ keys: [String: String]) -> [(key: String, value: String)] {
        let prefix = "crash_info_entry_"
        return keys
            .compactMap { key, value -> (index: Int, key: String, value: String)? in
                guard key.hasPrefix(prefix), let index = Int(key.dropFirst(prefix.count)) else { return nil }
                return (index, key, value)
            }
            .sorted { $0.index < $1.index }
            .map { ($0.key, $0.value) }
    }

    private static func crashMessage(from entries: [String]) -> String? {
        let lines = entries.flatMap(trimmedNonEmptyLines)
        let failures = lines.filter { line in failureMarkers.contains { line.contains($0) } }
        if !failures.isEmpty { return failures.joined(separator: "\n") }
        guard let last = entries.last else { return nil }
        return trimmedNonEmptyLines(last).last
    }

    private static func trimmedNonEmptyLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private extension Dictionary {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
