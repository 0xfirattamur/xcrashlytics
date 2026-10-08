struct CommandWarning: Equatable, Sendable {
    var code: String
    var message: String
    var path: String?

    init(code: WarningCode, message: String, path: String? = nil) {
        self.code = code.rawValue
        self.message = message
        self.path = path
    }

    var stderrLine: String {
        var line = "\(code): \(message)"
        if let path { line += " (\(path))" }
        return line
    }
}
