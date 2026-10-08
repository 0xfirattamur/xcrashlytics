import Foundation

extension CrashlyticsDTO {
    struct BreakdownReportResponse: Decodable, Sendable, Equatable {
        @CrashlyticsDTO.LossyList var groups: [BreakdownReportGroup]
        var nextPageToken: String?
    }

    // Exactly one of `version`, `operatingSystem` and `device` is set; device models nest as `subgroups`.
    struct BreakdownReportGroup: Decodable, Sendable, Equatable {
        var version: CrashlyticsDTO.Version?
        var operatingSystem: BreakdownReportOperatingSystem?
        var device: BreakdownReportDevice?
        @CrashlyticsDTO.LossyList var metrics: [BreakdownReportMetrics]
        @CrashlyticsDTO.LossyList var subgroups: [BreakdownReportGroup]

        var windowMetrics: BreakdownReportMetrics? { metrics.first }
    }

    struct BreakdownReportOperatingSystem: Decodable, Sendable, Equatable {
        var displayVersion: String?
        var os: String?
        var displayName: String?
    }

    struct BreakdownReportDevice: Decodable, Sendable, Equatable {
        var manufacturer: String?
        var model: String?
        var displayName: String?
        var marketingName: String?
    }

    struct BreakdownReportMetrics: Decodable, Sendable, Equatable {
        var eventsCount: CrashlyticsDTO.FlexibleInt?
        var impactedUsersCount: CrashlyticsDTO.FlexibleInt?
        var sessionsCount: CrashlyticsDTO.FlexibleInt?
        var impactedSessionsCount: CrashlyticsDTO.FlexibleInt?
        var totalUsersCount: CrashlyticsDTO.FlexibleInt?
        var totalSessionsCount: CrashlyticsDTO.FlexibleInt?
        var crashFreeUsersPercentage: Double?
        var crashFreeSessionsPercentage: Double?
        var startTime: String?

        private enum CodingKeys: String, CodingKey {
            case eventsCount, impactedUsersCount, sessionsCount, impactedSessionsCount, totalUsersCount
            case totalSessionsCount, crashFreeUsersPercentage, crashFreeSessionsPercentage, startTime
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func count(_ key: CodingKeys) throws -> CrashlyticsDTO.FlexibleInt? {
                try container.decodeIfPresent(CrashlyticsDTO.FlexibleInt.self, forKey: key)
            }
            eventsCount = try count(.eventsCount)
            impactedUsersCount = try count(.impactedUsersCount)
            sessionsCount = try count(.sessionsCount)
            impactedSessionsCount = try count(.impactedSessionsCount)
            totalUsersCount = try count(.totalUsersCount)
            totalSessionsCount = try count(.totalSessionsCount)
            // An unexpected shape is an absent percentage, not a failed page.
            crashFreeUsersPercentage = try? container.decodeIfPresent(Double.self, forKey: .crashFreeUsersPercentage)
            crashFreeSessionsPercentage = try? container.decodeIfPresent(
                Double.self, forKey: .crashFreeSessionsPercentage)
            startTime = try? container.decodeIfPresent(String.self, forKey: .startTime)
        }
    }
}
