import Foundation

struct TaskSleeper: Sleeper {
    func sleep(seconds: Double) async throws {
        guard seconds.isFinite, seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 3_600) * 1_000_000_000))
    }
}
