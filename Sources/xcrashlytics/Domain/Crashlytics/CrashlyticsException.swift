import Foundation

struct CrashlyticsException: Sendable, Equatable {
    var type: String?
    var exceptionMessage: String?
    var title: String?
    var subtitle: String?
    var blamed: Bool
    var frames: [CrashlyticsFrame]

    init(
        type: String? = nil,
        exceptionMessage: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        blamed: Bool = false,
        frames: [CrashlyticsFrame] = []
    ) {
        self.type = type
        self.exceptionMessage = exceptionMessage
        self.title = title
        self.subtitle = subtitle
        self.blamed = blamed
        self.frames = frames
    }
}
