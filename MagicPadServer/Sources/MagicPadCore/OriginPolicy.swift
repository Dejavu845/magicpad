// OriginPolicy.swift
// Pure WebSocket / HTTP Origin allowlist (no Network / no AppKit).
// Missing/empty Origin → allow (curl / python smokes). "null" → reject.

import Foundation

public enum OriginPolicy {
    /// Hosts always accepted besides `lanIPs` (loopback).
    public static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    public struct Parsed: Equatable, Sendable {
        public let scheme: String
        public let host: String
    }

    /// Shared parse for `isAllowed` and `host(fromOrigin:)`.
    /// Rejects non-http(s)/ws(s), userinfo, query, fragment, non-root path,
    /// and percent-encoded hosts. Trailing `/` on the origin string is stripped
    /// first so `http://127.0.0.1:7878/` still parses as root.
    public static func parse(origin: String) -> Parsed? {
        var s = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.lowercased() != "null" else { return nil }
        while s.hasSuffix("/") { s.removeLast() }
        guard let comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased() else {
            return nil
        }
        let schemes: Set<String> = ["http", "https", "ws", "wss"]
        guard schemes.contains(scheme) else { return nil }
        if comps.user != nil || comps.password != nil { return nil }
        if comps.query != nil || comps.fragment != nil { return nil }
        let path = comps.path
        if !path.isEmpty && path != "/" { return nil }
        let rawHost = comps.percentEncodedHost ?? comps.host
        guard let rawHost, !rawHost.isEmpty else { return nil }
        if rawHost.contains("%") { return nil }
        let host = rawHost.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return Parsed(scheme: scheme, host: host)
    }

    /// Host for reject logs. Same parse as `isAllowed` (scheme required).
    /// `file://127.0.0.1` → nil. Never use as an access decision.
    public static func host(fromOrigin origin: String?) -> String? {
        guard let origin else { return nil }
        return parse(origin: origin)?.host
    }

    /// `nil` / empty → true (no Origin header). `"null"` (opaque) → false.
    /// Allowed schemes: http | https | ws | wss.
    /// Host must be loopback or in `lanIPs` (case-insensitive; brackets stripped).
    public static func isAllowed(origin: String?, lanIPs: [String]) -> Bool {
        guard let origin else { return true }
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.lowercased() == "null" { return false }
        guard let parsed = parse(origin: trimmed) else { return false }
        var allowed = loopbackHosts
        for ip in lanIPs {
            let h = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if !h.isEmpty { allowed.insert(h) }
        }
        return allowed.contains(parsed.host)
    }
}
