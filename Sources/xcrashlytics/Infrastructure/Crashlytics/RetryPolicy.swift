import Foundation

struct RetryPolicy: Sendable {
    var maxRetries: Int
    // Offline or timed-out requests give up sooner than rate limiting and server errors.
    var maxTransportRetries: Int
    var baseDelay: Double = 1
    var maxDelay: Double = 60
    var maxRetryAfter: Double = 120
    // Multiplier in 0.5...1 so concurrent requests do not retry in lockstep.
    var jitter: @Sendable () -> Double

    static let randomJitter: @Sendable () -> Double = { Double.random(in: 0.5...1) }

    init(maxRetries: Int, jitter: @escaping @Sendable () -> Double = RetryPolicy.randomJitter) {
        self.maxRetries = max(0, maxRetries)
        self.maxTransportRetries = min(max(0, maxRetries), 2)
        self.jitter = jitter
    }

    func delay(attempt: Int, retryAfter header: String?, now: Date) -> Double {
        if let requested = Self.retryAfterSeconds(header, now: now) {
            return min(requested, maxRetryAfter)
        }
        return backoff(attempt: attempt)
    }

    func backoff(attempt: Int) -> Double {
        min(baseDelay * pow(2, Double(min(attempt, 30))), maxDelay) * jitter()
    }

    // `Retry-After` is delta-seconds or an HTTP date.
    static func retryAfterSeconds(_ header: String?, now: Date) -> Double? {
        guard let value = header?.trimmedNonEmpty else { return nil }
        if let seconds = Double(value), seconds.isFinite {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
