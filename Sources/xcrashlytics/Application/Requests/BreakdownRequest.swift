struct BreakdownRequest: Sendable {
    /// nil reports the whole app.
    var issue: String?
    var dimension: BreakdownDimension
    var since: String
    var limit: Int?
}
