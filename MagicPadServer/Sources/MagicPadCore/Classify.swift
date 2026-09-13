// Classify.swift
// Cycle 30: two-finger classify is telemetry only (MP-12).
// Never HID inject. Pairing token is not involved.

import Foundation

public enum Classify {
    public static let jsonType = "classify"
    public static let ackType = "classify_ack"
    public static let injects = false

    public static func parseKind(_ raw: String?) -> String? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
