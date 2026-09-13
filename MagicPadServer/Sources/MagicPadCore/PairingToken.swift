// PairingToken.swift
// Optional LAN pairing hatch. Default OFF (empty env).
// Never appears in GET /health. Cycle 20. Local hello wire.

import Foundation

public enum PairingToken {
    public static let envName = "MAGICPAD_PAIRING_TOKEN"
    public static let helloField = "pair"
    public static let rejectedReason = "pairing_rejected"

    public static func configured(
        _ read: (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> String? {
        let raw = (read(envName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Off → allow. On → `hello.pair` must equal the env value.
    public static func allows(_ provided: String?, configured: String? = nil) -> Bool {
        let want = configured ?? Self.configured()
        guard let want else { return true }
        let got = (provided ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return got == want
    }
}
