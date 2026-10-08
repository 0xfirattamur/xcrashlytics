import Foundation

struct BreakdownRecord: Encodable, Sendable {
    var row: BreakdownRowPayload

    private enum CodingKeys: String, CodingKey { case kind }

    func encode(to encoder: Encoder) throws {
        try row.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("breakdownRow", forKey: .kind)
    }
}
