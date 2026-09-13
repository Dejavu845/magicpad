// HTTPHeaderValue.swift
// Cycle 7 wired handshake Origin / key / version. Cycle 8 replaces the last
// WebSocketServer.headerValue call sites in beginHTTPPost (filename / length /
// type / lang / autopaste). Empty `Name:` is "" , not the header name.

import Foundation

public enum HTTPHeaderValue {
    /// First `Name:` value in a raw HTTP/1.1 header blob.
    /// Missing → `nil`. Present-but-empty (`Origin:\r\n`) → `""` (not `"Origin"`).
    /// Uses `omittingEmptySubsequences: false` so a trailing empty piece is kept.
    public static func first(_ blob: String, name: String) -> String? {
        let target = name.lowercased() + ":"
        let normalized = blob.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let lower = line.lowercased()
            guard lower.hasPrefix(target) else { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count < 2 { return "" }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
