/// Resolves addresses in Crashlytics frames to symbols with local debug symbols.
protocol FrameSymbolizer: Sendable {
    /// Returns `events` with frames resolved from the dSYMs at `dsymPaths`;
    /// problems are reported as warnings, never thrown.
    func symbolicate(_ events: [CrashlyticsEvent], dsymPaths: [String]) -> SymbolicationResult
}
