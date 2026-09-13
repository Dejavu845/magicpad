// CertRoute.swift
// GET /cert whitelist (MP-22). Only the public DER `magicpad-lan.cer`.
// Never serve .pem / .p12 / .key. Cycle 15. Local WebSocketServer wires this.

import Foundation

public enum CertRoute {
    public static let path = "/cert"
    public static let filename = "magicpad-lan.cer"
    public static let contentType = "application/x-x509-ca-cert"
    public static let contentDisposition = "attachment; filename=\"magicpad-lan.cer\""
    public static let missingBody = "cert_not_ready"
    public static let forbiddenBody = "cert_forbidden"
    public static let refusedSuffixes: [String] = [".pem", ".p12", ".key"]

    public static func normalizedPath(_ raw: String) -> String {
        var clean = raw.split(separator: "?").first.map(String.init) ?? raw
        if let decoded = clean.removingPercentEncoding {
            clean = decoded
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.count > 1 && clean.hasSuffix("/") {
            clean.removeLast()
        }
        if clean.isEmpty { return "/" }
        return clean
    }

    /// Exact `/cert` only. Query / trailing slash stripped. No `.cer` alias path.
    public static func allowsGET(_ rawPath: String) -> Bool {
        normalizedPath(rawPath) == path
    }

    public static func refusesSecretExport(_ rawPath: String) -> Bool {
        let p = normalizedPath(rawPath).lowercased()
        return refusedSuffixes.contains { p.hasSuffix($0) }
    }
}
