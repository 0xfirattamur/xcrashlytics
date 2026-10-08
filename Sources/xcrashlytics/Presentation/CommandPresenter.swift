protocol CommandPresenter {
    associatedtype Result
    func render(_ result: Result, format: OutputFormat) throws -> RenderedOutput
}
