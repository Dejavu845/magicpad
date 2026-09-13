// HTTPPostOrigin.swift
// Core helper for the HTTP POST Origin check. Cycle 7 wires
// `HTTPPostOrigin.allows` in `beginHTTPPost` (docs/CYCLE3-HTTP-ORIGIN.md).
// CORS echo is not this check.

import Foundation

public enum HTTPPostOrigin {
    /// Same missing/empty Origin carve-out as the WebSocket handshake (curl smokes).
    public static func allows(_ origin: String?, lanIPs: [String]) -> Bool {
        OriginPolicy.isAllowed(origin: origin, lanIPs: lanIPs)
    }
}
