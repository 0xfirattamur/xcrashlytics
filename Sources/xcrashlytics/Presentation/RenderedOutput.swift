struct RenderedOutput: Sendable {
    var body: String
    /// JSON embeds warnings in its envelope, so the emitter skips them for that format.
    var warnings: [CommandWarning] = []
}
