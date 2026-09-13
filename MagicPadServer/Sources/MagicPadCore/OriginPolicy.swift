// OriginPolicy.swift
// Pure WebSocket Origin allowlist (no Network / no AppKit).
// Missing/empty Origin → allow (curl / python smokes). "null" → reject.

import Foundation

public enum OriginPolicy {
    /// Hosts always accepted besides `lanIPs` (loopback).
    public static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    public static func host(fromOrigin origin: String?) -> String? {
        guard let origin else { return nil }
        var s = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.lowercased() != "null" else { return nil }
        while s.hasSuffix("/") { s.removeLast() }
        guard let comps = URLComponents(string: s), let host = comps.host else { return nil }
        return host
    }

    /// `nil` / empty → true (no Origin header). `"null"` (opaque) → false.
    /// Allowed schemes: http | https | ws | wss.
    /// Host must be loopback or in `lanIPs` (case-insensitive; brackets stripped).
    public static func isAllowed(origin: String?, lanIPs: [String]) -> Bool {
        guard let origin else { return true }
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.lowercased() == "null" { return false }
        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        guard let comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased(),
              let hostRaw = comps.host else {
            return false
        }
        let schemes: Set<String> = ["http", "https", "ws", "wss"]
        guard schemes.contains(scheme) else { return false }
        let host = hostRaw.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var allowed = loopbackHosts
        for ip in lanIPs {
            let h = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if !h.isEmpty { allowed.insert(h) }
        }
        return allowed.contains(host)
    }
}
