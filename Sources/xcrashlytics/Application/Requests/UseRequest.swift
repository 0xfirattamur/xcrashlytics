struct UseRequest: Sendable, Equatable {
    /// As typed: echoed verbatim in "not found" errors.
    let profile: String
}
