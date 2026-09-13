// CORSPolicy.swift
// Echo an allowlisted Origin; keep * only when Origin is missing (curl).
// Echo is NOT the write control. Cycle 7 wired HTTPPostOrigin.allows in
// local beginHTTPPost; this type only decides Access-Control-Allow-Origin.

import Foundation

public enum CORSPolicy {
    public struct AccessControl: Equatable, Sendable {
        public let allowOrigin: String
        public let needsVary: Bool
    }

    /// Missing / empty Origin → `*` and no Vary (smoke-all curl).
    /// Allowlisted Origin → echo the trimmed header and `needsVary == true`.
    /// Disallowed → `nil` (omit Access-Control-Allow-Origin).
    public static func accessControl(
        origin: String?,
        lanIPs: [String]
    ) -> AccessControl? {
        guard let origin else {
            return AccessControl(allowOrigin: "*", needsVary: false)
        }
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AccessControl(allowOrigin: "*", needsVary: false)
        }
        if OriginPolicy.isAllowed(origin: origin, lanIPs: lanIPs) {
            return AccessControl(allowOrigin: trimmed, needsVary: true)
        }
        return nil
    }
}
