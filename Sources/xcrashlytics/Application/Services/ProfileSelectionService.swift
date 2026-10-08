struct ProfileSelectionService: Sendable {
    let configRepository: ConfigRepository

    func use(_ request: UseRequest) throws -> UseResult {
        guard let name = request.profile.trimmedNonEmpty?.lowercased() else {
            throw InvalidInputError("profile name must not be empty.")
        }
        var config = try configRepository.load()
        guard let existing = config.profiles[name] else {
            throw InvalidInputError(
                "profile '\(request.profile)' not found. Add it with "
                    + "`xcrashlytics init --profile \(request.profile) --app-id <GOOGLE_APP_ID>`.")
        }
        config.activeProfile = name
        try configRepository.save(config)
        return UseResult(profile: name, appId: existing.appId)
    }
}
