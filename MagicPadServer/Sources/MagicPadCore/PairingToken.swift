// PairingToken.swift
// Optional LAN pairing hatch. Default OFF (empty env).
// Never appears in GET /health. Cycle 20. Local hello wire.
// Cycle 21: QR / --print-only / mobileURL must never embed this token.

import Foundation

public enum PairingToken {
    public static let envName = "MAGICPAD_PAIRING_TOKEN"
    public static let helloField = "pair"
    public static let rejectedReason = "pairing_rejected"
    /// Cycle 29: these must never be GET /health keys (hello-only hatch).
    public static let forbiddenHealthKeys: Set<String> = [helloField, envName, Classify.jsonType]

    public static func healthAllowsKey(_ key: String) -> Bool {
        !forbiddenHealthKeys.contains(key)
    }

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

    /// Cycle 21/22: QR encodes only scheme/host/port plus optional auto=1.
    /// A photographed QR must not leak MAGICPAD_PAIRING_TOKEN.
    public static func qrURLIsSafe(_ url: String, configured: String? = nil) -> Bool {
        let lowered = url.lowercased()
        if lowered.contains("pair=") { return false }
        if lowered.contains("classify=") { return false }
        if url.contains(envName) { return false }
        let token = (configured ?? Self.configured() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty && url.contains(token) { return false }
        if let comps = URLComponents(string: url),
           let items = comps.queryItems,
           items.contains(where: { $0.name.lowercased() == helloField }) {
            return false
        }
        return true
    }
}
