struct ResultEmitter: Sendable {
    let console: Console

    @discardableResult
    func emit(_ output: RenderedOutput, format: OutputFormat) -> String {
        report(output.warnings, format: format)
        console.writeOutput(output.body)
        return output.body
    }

    /// Non-JSON formats report warnings on stderr; JSON embeds them in its envelope instead.
    /// Call before a side effect that can fail so the warnings are not lost with it.
    func report(_ warnings: [CommandWarning], format: OutputFormat) {
        guard format != .json else { return }
        for warning in warnings { console.reportWarning(warning.stderrLine) }
    }

    @discardableResult
    func emit<Presenter: CommandPresenter>(
        _ result: Presenter.Result, using presenter: Presenter, format: OutputFormat
    ) throws -> String {
        emit(try presenter.render(result, format: format), format: format)
    }
}
