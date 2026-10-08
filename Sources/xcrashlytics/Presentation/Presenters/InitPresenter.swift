/// `init` has no machine-readable mode, so every format gets the same text.
struct InitPresenter: CommandPresenter {
    var text = InitTextRenderer()

    func render(_ result: InitResult, format: OutputFormat) -> RenderedOutput {
        RenderedOutput(body: text.render(result))
    }
}
