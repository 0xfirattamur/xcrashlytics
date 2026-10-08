struct OpenResult: Sendable, Equatable {
    var target: Target

    enum Target: Sendable, Equatable {
        case source(path: String, line: Int?)
        /// No frame's file could be resolved, so the report opens as-is; `reason` says why.
        case rawReport(path: String, reason: String)
    }
}

/// Decided but not yet launched.
struct OpenPlan: Sendable, Equatable {
    var target: OpenResult.Target
    var warnings: [CommandWarning]
}
