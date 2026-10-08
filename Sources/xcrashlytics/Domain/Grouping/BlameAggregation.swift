struct BlameAggregation: Sendable {
    var rows: [BlameSummary]
    var sampledEvents: Int
}
