struct GroupsPayload: Encodable, Sendable {
    var window: ReportWindowSummary
    var groups: [GroupRecord]
}
