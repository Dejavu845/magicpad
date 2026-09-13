// CORSPolicy.swift
// Echo an allowlisted Origin; keep * only when Origin is missing (curl).
// Echo is NOT the write control — beginHTTPPost still needs HTTPPostOrigin.

import Foundation

public enum CORSPolicy {
    /// Missing / empty Origin → `*` (smoke-all curl).
    /// Allowlisted Origin → echo the trimmed header (plus caller should send Vary).
    /// Disallowed → `nil` (omit Access-Control-Allow-Origin).
    public static func accessControlAllowOrigin(
        origin: String?,
        lanIPs: [String]
    ) -> String? {
        guard let origin else { return "*" }
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "*" }
        if OriginPolicy.isAllowed(origin: origin, lanIPs: lanIPs) {
            return trimmed
        }
        return nil
    }
}
