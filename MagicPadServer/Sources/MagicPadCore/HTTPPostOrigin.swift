// HTTPPostOrigin.swift
// Core helper for the HTTP POST Origin check. beginHTTPPost does not call
// this yet — POST /drop and POST /stt still have no Origin check. Insertion
// is documented in docs/CYCLE3-HTTP-ORIGIN.md. CORS * is not this check.

import Foundation

public enum HTTPPostOrigin {
    /// Same missing/empty Origin carve-out as the WebSocket handshake (curl smokes).
    public static func allows(_ origin: String?, lanIPs: [String]) -> Bool {
        OriginPolicy.isAllowed(origin: origin, lanIPs: lanIPs)
    }
}
