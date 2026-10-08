import Foundation

extension CrashlyticsDTO.EventsResponse {
    // Keeps each event's raw JSON so fields without a typed property stay searchable.
    // An undecodable event is skipped; a body that is not an events page throws.
    static func decodePreservingRawEvents(from data: Data) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CrashlyticsDTO.DecodeFailure.notAnObject
        }
        let rawEvents = (root["events"] as? [Any]) ?? []
        var events: [CrashlyticsDTO.Event] = []
        for rawEvent in rawEvents {
            guard JSONSerialization.isValidJSONObject(rawEvent),
                  let eventData = try? JSONSerialization.data(withJSONObject: rawEvent, options: [.sortedKeys]),
                  var event = try? JSONDecoder().decode(CrashlyticsDTO.Event.self, from: eventData)
            else { continue }
            event.rawJSON = String(data: eventData, encoding: .utf8)
            events.append(event)
        }
        return Self(events: events, nextPageToken: root["nextPageToken"] as? String)
    }
}

extension CrashlyticsDTO {
    enum DecodeFailure: Error {
        case notAnObject
    }

    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "the body is not the expected JSON object"
        }
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return joined.isEmpty ? "the body" : String(joined.drop(while: { $0 == "." }))
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "missing field '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "unexpected value at \(path(context))"
        case .dataCorrupted:
            return "the body is not valid JSON"
        @unknown default:
            return "unreadable response"
        }
    }
}
