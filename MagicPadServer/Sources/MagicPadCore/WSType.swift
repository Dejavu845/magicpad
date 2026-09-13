// WSType.swift
// Cycle 27: inbound JSON `type` allowlist lives in Core (MP-18).
// Unknown / missing / wrong case → nil (ignore, no inject).
// Does not invent drop/upload as WS types (those are HTTP POST).

import Foundation

public enum WSType: String, Sendable {
    case voice
    case key
    case type
    case text
    case stt
    case hello
    case ping
    case classify

    public static let inbound: Set<String> = [
        "voice", "key", "type", "text", "stt", "hello", "ping", "classify",
    ]

    /// Exact JSON string. Trim only. Case-sensitive. Else nil.
    public static func parse(_ raw: String?) -> WSType? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return WSType(rawValue: key)
    }
}
