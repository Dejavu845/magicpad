// LANAddress.swift
// RFC1918 IPv4 check. Cycle 6: split first, require exactly four components,
// then parse, then 0...255 — do not compactMap before the count (that treated
// "10.a.0.0.1" as a 10/8 address). Same rule belongs in LANDetector.isPrivate.

import Foundation

public enum LANAddress {
    /// True for 10/8, 172.16/12, 192.168/16. False for loopback, link-local, public.
    public static func isPrivate(_ ip: String) -> Bool {
        let tokens = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard tokens.count == 4 else { return false }
        var parts: [Int] = []
        parts.reserveCapacity(4)
        for token in tokens {
            // One to three ASCII digits. Reject "+" / "-" / "_" that Int(String)
            // would accept (Opus C7 M6). Same rule as scripts/magicpad_proto.py.
            let ascii = token.utf8
            guard (1...3).contains(ascii.count),
                  ascii.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let n = Int(token), (0...255).contains(n) else { return false }
            parts.append(n)
        }
        if parts[0] == 127 { return false }
        if parts[0] == 169 && parts[1] == 254 { return false }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}
