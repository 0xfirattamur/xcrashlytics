import ArgumentParser

extension IssuesCommand {
    func validateInputs() throws {
        try OptionValidator.requirePositive(limit, flag: "--limit")
        try OptionValidator.requirePositive(searchLimit, flag: "--search-limit")
        try OptionValidator.requirePositive(eventsPerIssue, flag: "--events-per-issue")
        if let minEvents, minEvents < 0 {
            throw ValidationError("--min-events must not be negative; got \(minEvents).")
        }
        try OptionValidator.requireNonEmpty(query, flag: "the query")
        try OptionValidator.requireNonEmpty(match, flag: "--match")
        try OptionValidator.requireNonEmpty(type, flag: "--type")
        try OptionValidator.requireNonEmpty(appVersion, flag: "--app-version")
        try OptionValidator.requireNonEmpty(sinceVersion, flag: "--since-version")
        try OptionValidator.requireNonEmpty(file, flag: "--file")
        try OptionValidator.requireNonEmpty(symbol, flag: "--symbol")
        try OptionValidator.requireNonEmpty(userId, flag: "--user-id")
        try OptionValidator.requireNonEmpty(domain, flag: "--domain")
        for key in userInfoKey { try OptionValidator.requireNonEmpty(key, flag: "--user-info-key") }
        if let appVersion { _ = try AppVersion.require(appVersion, flag: "--app-version") }
        if let sinceVersion { _ = try AppVersion.require(sinceVersion, flag: "--since-version") }
    }
}
