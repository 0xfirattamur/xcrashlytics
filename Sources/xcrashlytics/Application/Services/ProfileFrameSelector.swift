struct ProfileFrameSelector: Sendable {
    let configRepository: ConfigRepository

    // An unreadable config contributes no libraries; commands that need the config fail on their own.
    func selector() -> FrameSelector {
        let appLibraries = (try? configRepository.load())?.resolvedAppLibraries ?? []
        return FrameSelector(classifier: FrameClassifier(appLibraries: appLibraries))
    }
}
