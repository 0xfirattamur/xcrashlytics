enum SetupCheck: Equatable, Sendable {
    case ok
    case warn(String)
    case fail(String, hint: [String] = [])

    var blocks: Bool {
        if case .fail = self { return true }
        return false
    }

    var passed: Bool {
        if case .ok = self { return true }
        return false
    }

    var warns: Bool {
        if case .warn = self { return true }
        return false
    }
}
