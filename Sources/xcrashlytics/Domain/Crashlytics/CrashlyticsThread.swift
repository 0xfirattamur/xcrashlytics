import Foundation

struct CrashlyticsThread: Sendable, Equatable {
    var name: String?
    var title: String?
    var subtitle: String?
    var crashed: Bool
    // Crashlytics quirk: ANRs and non-fatals have no crashed thread, only a blamed one.
    var blamed: Bool
    var signal: String?
    var signalCode: String?
    var crashAddress: String?
    var queue: String?
    var frames: [CrashlyticsFrame]

    init(
        name: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        crashed: Bool = false,
        blamed: Bool = false,
        signal: String? = nil,
        signalCode: String? = nil,
        crashAddress: String? = nil,
        queue: String? = nil,
        frames: [CrashlyticsFrame] = []
    ) {
        self.name = name
        self.title = title
        self.subtitle = subtitle
        self.crashed = crashed
        self.blamed = blamed
        self.signal = signal
        self.signalCode = signalCode
        self.crashAddress = crashAddress
        self.queue = queue
        self.frames = frames
    }
}
