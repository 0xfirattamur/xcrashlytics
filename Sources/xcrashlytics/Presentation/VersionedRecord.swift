/// One NDJSON record: the value's own keys plus `schemaVersion`.
struct VersionedRecord<T: Encodable>: Encodable {
    var value: T

    private enum CodingKeys: String, CodingKey { case schemaVersion }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputSchemaVersion, forKey: .schemaVersion)
    }
}
