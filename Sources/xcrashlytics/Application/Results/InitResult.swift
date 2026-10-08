struct InitResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case blocked
        case written(activeProfile: String?)
    }

    let discovered: [DiscoveredFirebaseApp]
    let libraries: [String]
    let checks: [SetupCheck]
    let outcome: Outcome

    var isBlocked: Bool { outcome == .blocked }
    var hasWarnings: Bool { checks.contains { $0.warns } }
}
