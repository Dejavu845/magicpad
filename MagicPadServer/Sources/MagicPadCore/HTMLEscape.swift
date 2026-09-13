// HTMLEscape.swift
// Escape untrusted text before interpolating into fallbackHTML (Opus H1).
// Wire in WebSocketServer.fallbackHTML after the 62 KB file is restored.

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

    public static let errorPageCSP = "default-src 'none'"
    public static let nosniff = "nosniff"
}
