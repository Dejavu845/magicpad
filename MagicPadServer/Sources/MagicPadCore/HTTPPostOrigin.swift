// HTTPPostOrigin.swift
// Cycle 3 (owner `git push` of WebSocketServer.swift): call from beginHTTPPost.
// Exact insertion is documented in docs/CYCLE3-HTTP-ORIGIN.md — do not pretend
// MP-01 already closed POST /drop. CORS * is not this check.

import Foundation

public enum HTTPPostOrigin {
    /// Same missing/empty Origin carve-out as the WebSocket handshake (curl smokes).
    public static func allows(_ origin: String?, lanIPs: [String]) -> Bool {
        OriginPolicy.isAllowed(origin: origin, lanIPs: lanIPs)
    }
}
