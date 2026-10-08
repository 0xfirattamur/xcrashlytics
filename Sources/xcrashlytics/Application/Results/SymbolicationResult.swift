struct SymbolicationResult: Sendable {
    var events: [CrashlyticsEvent]
    var warnings: [CommandWarning]
}
