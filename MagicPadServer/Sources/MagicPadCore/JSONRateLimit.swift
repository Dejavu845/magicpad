// JSONRateLimit.swift
// Token bucket for type / text / voice JSON only (MP-23).
// Never meters binary 13/18-byte frames (120 Hz). key / ping / hello / stt
// / classify always pass. Cycle 13 wired locally in handleJSONText.

import Foundation

public final class JSONRateLimit: @unchecked Sendable {
    public static let shared = JSONRateLimit()
    public static let meteredTypes: Set<String> = ["type", "text", "voice"]

    private let lock = NSLock()
    private let tokensPerSec: Double
    private let burst: Double
    private var tokens: Double
    private var lastRefill: TimeInterval

    public init(
        tokensPerSec: Double = Double(ProtocolLimits.jsonTokensPerSec),
        burst: Double = Double(ProtocolLimits.jsonBurst)
    ) {
        self.tokensPerSec = tokensPerSec
        self.burst = burst
        self.tokens = burst
        self.lastRefill = 0
    }

    public func allow(_ type: String, now: TimeInterval) -> Bool {
        guard Self.meteredTypes.contains(type) else { return true }
        lock.lock()
        defer { lock.unlock() }
        if lastRefill == 0 {
            lastRefill = now
        }
        let dt = max(0, now - lastRefill)
        tokens = min(burst, tokens + dt * tokensPerSec)
        lastRefill = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    public func allow(_ type: String) -> Bool {
        allow(type, now: Date().timeIntervalSince1970)
    }

    public func reset(now: TimeInterval = 0) {
        lock.lock()
        tokens = burst
        lastRefill = now
        lock.unlock()
    }
}
