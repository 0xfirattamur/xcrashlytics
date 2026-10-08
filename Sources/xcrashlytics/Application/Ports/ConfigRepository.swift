protocol ConfigRepository: Sendable {
    /// The stored config, or an empty one when none exists yet.
    func load() throws -> Config
    func save(_ config: Config) throws
}
