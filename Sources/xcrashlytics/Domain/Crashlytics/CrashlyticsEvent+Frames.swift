import Foundation

extension CrashlyticsEvent {
    var hasCrashedThread: Bool {
        threads.contains(where: \.crashed)
    }
}
