struct OpenPresenter: CommandPresenter {
    func render(_ result: OpenResult, format: OutputFormat) throws -> RenderedOutput {
        let body: String
        switch result.target {
        case let .source(path, line):
            body = "Opened \(line.map { "\(path):\($0)" } ?? path) in Xcode.\n"
        case let .rawReport(path, reason):
            body = "Opened raw report at \(path) (\(reason)).\n"
        }
        return RenderedOutput(body: body)
    }
}
