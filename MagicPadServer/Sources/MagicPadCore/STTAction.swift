// STTAction.swift
// Cycle 23: STT JSON action aliases live in Core (MP-18 / MP-12).
// start/begin/on · stop/end/off · status. Unknown → nil (bad_action).
// No inject. On-device only. Pairing token is not involved.

import Foundation

public enum STTAction: String, Sendable {
    case start
    case stop
    case status

    public static let startAliases: Set<String> = ["start", "begin", "on"]
    public static let stopAliases: Set<String> = ["stop", "end", "off"]
    public static let statusAliases: Set<String> = ["status"]

    public static func parse(_ raw: String?) -> STTAction? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if startAliases.contains(key) { return .start }
        if stopAliases.contains(key) { return .stop }
        if statusAliases.contains(key) { return .status }
        return nil
    }
}
