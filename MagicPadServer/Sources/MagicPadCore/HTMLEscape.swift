// HTMLEscape.swift
// Escape untrusted text before interpolating into fallbackHTML (Opus H1).
// Cycle 7 wired this in local WebSocketServer.fallbackHTML. Remote stub unrestored.
// This is for a text-content sink (`<p>`). It does not escape backtick or `=`;
// do not reuse it for an unquoted attribute value.

import Foundation

public enum HTMLEscape {
    public static func escape(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    public static let errorPageCSP = "default-src 'none'; style-src 'unsafe-inline'"
    public static let nosniff = "nosniff"
}
