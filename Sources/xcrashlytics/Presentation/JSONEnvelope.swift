/// Version of the JSON / NDJSON output contract. Bumped only on breaking changes.
let outputSchemaVersion = 1

struct JSONEnvelope<T: Encodable>: Encodable {
    var schemaVersion = outputSchemaVersion
    var data: T
    var warnings: [WarningPayload]
}
