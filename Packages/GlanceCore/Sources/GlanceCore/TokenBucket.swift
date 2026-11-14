import Foundation

public struct RateDecision: Equatable, Sendable {
    public var allowed: Bool
    public var retryAfter: TimeInterval
    public var remainingTokens: Double

    public init(allowed: Bool, retryAfter: TimeInterval, remainingTokens: Double) {
        self.allowed = allowed
        self.retryAfter = retryAfter
        self.remainingTokens = remainingTokens
    }
}

/// Token bucket. Callers pass `at` so tests can move time without sleeping.
public actor TokenBucket {
    private let capacity: Double
    private let refillPerSecond: Double
    private var tokens: Double
    private var last: Date

    public init(capacity: Double, refillPerSecond: Double, now: Date = Date()) {
        self.capacity = max(0, capacity)
        self.refillPerSecond = max(0, refillPerSecond)
        self.tokens = max(0, capacity)
        self.last = now
    }

    public func tryConsume(_ amount: Double = 1, at now: Date = Date()) -> RateDecision {
        let cost = max(0, amount)
        refill(to: now)
        if tokens >= cost {
            tokens -= cost
            return RateDecision(allowed: true, retryAfter: 0, remainingTokens: tokens)
        }
        let deficit = cost - tokens
        let retryAfter = refillPerSecond > 0 ? deficit / refillPerSecond : TimeInterval.infinity
        return RateDecision(allowed: false, retryAfter: retryAfter, remainingTokens: tokens)
    }

    private func refill(to now: Date) {
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else {
            if elapsed < 0 { last = now }
            return
        }
        tokens = min(capacity, tokens + (elapsed * refillPerSecond))
        last = now
    }
}
