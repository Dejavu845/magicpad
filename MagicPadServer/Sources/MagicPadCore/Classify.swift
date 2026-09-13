// Classify.swift
// Cycle 30: two-finger classify is telemetry only (MP-12).
// Never HID inject. Pairing token is not involved.

import Foundation

public enum Classify {
    public static let jsonType = "classify"
    public static let ackType = "classify_ack"
    public static let injects = false
    /// Cycle 32: telemetry type only. Never a GET /health key.
    public static let isHealthKey = false
    /// Cycle 33: WS telemetry only. There is no HTTP /classify route.
    public static let httpPath: String? = nil

    public static func parseKind(_ raw: String?) -> String? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
