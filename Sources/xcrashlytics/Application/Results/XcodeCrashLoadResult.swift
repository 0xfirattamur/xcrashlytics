struct XcodeCrashLoadResult: Sendable {
    var crashes: [XcodeCrash]
    var warnings: [CommandWarning]
}
