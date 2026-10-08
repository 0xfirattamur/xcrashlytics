protocol AppDiscovery: Sendable {
    func discover(from root: String) throws -> AppDiscoveryResult
}
