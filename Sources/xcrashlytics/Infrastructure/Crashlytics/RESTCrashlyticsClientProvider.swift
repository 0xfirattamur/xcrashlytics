import Foundation

struct RESTCrashlyticsClientProvider: CrashlyticsClientProvider {
    let configRepository: ConfigRepository
    let httpClient: HTTPClient
    let sleeper: Sleeper
    let dateProvider: DateProvider
    let accessTokens: @Sendable () -> AccessTokenProvider

    func client() throws -> CrashlyticsClient {
        try client(appId: nil)
    }

    func client(for link: FirebaseConsoleLink) throws -> CrashlyticsClient {
        guard let appId = try configRepository.load().appId(for: link) else {
            throw InvalidInputError(
                "no profile for bundle id '\(link.bundleId)'. Add one: "
                    + "xcrashlytics init --app-id <APP_ID> --bundle-id \(link.bundleId) --profile <name>")
        }
        return try client(appId: appId)
    }

    private func client(appId override: String?) throws -> CrashlyticsClient {
        let config = try configRepository.load()
        guard let appId = override ?? config.resolvedAppId else {
            throw ConfigError.missingAppId
        }
        return try RESTCrashlyticsClient(
            httpClient: httpClient, tokens: accessTokens(), sleeper: sleeper, appId: appId, dateProvider: dateProvider)
    }
}
