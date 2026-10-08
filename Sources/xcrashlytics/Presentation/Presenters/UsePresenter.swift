/// `use` has no machine-readable mode, so every format gets the same text.
struct UsePresenter: CommandPresenter {
    func render(_ result: UseResult, format: OutputFormat) -> RenderedOutput {
        RenderedOutput(body: "Using profile \(result.profile) (\(result.appId)).\n")
    }
}
