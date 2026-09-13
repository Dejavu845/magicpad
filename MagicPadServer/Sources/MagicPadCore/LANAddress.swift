// LANAddress.swift
// Pure IPv4 RFC1918 check copied from LANDetector.isPrivate (no getifaddrs).

import Foundation

public enum LANAddress {
    /// True for 10/8, 172.16/12, 192.168/16. False for loopback, link-local, public.
    public static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 127 { return false }
        if parts[0] == 169 && parts[1] == 254 { return false }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}
