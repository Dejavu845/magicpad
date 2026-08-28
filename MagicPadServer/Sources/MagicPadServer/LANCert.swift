// LANCert.swift
// Self-signed LAN TLS identity for HTTPS/WSS (iPhone getUserMedia secure context).
// HTTP :7878 remains primary for smoke; HTTPS :7879 optional when cert ready.
// No product LLM. No Continuity/BT.

import Foundation
import Network
import Security

enum LANCert {
    static let httpPort: UInt16 = 7878
    static let httpsPort: UInt16 = 7879
    /// PKCS#12 export passphrase (local-only; not a user secret).
    private static let p12Pass = "magicpad-lan"
    private static let certCommonName = "MagicPad-LAN"

    private static let lock = NSLock()
    // Locked access; Swift 6 global mutable → nonisolated(unsafe) like InjectTelemetry
    nonisolated(unsafe) private static var cachedIdentity: SecIdentity?
    nonisolated(unsafe) private static var cachedReady = false
    nonisolated(unsafe) private static var lastError: String = ""

    static var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedReady && cachedIdentity != nil
    }

    static var statusError: String {
        lock.lock(); defer { lock.unlock() }
        return lastError
    }

    /// Directory: ~/Library/Application Support/MagicPad/
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MagicPad", isDirectory: true)
    }

    static var p12URL: URL { supportDir.appendingPathComponent("magicpad-lan.p12") }
    static var cerURL: URL { supportDir.appendingPathComponent("magicpad-lan.cer") }
    static var pemCertURL: URL { supportDir.appendingPathComponent("magicpad-lan-cert.pem") }
    static var pemKeyURL: URL { supportDir.appendingPathComponent("magicpad-lan-key.pem") }
    /// Dedicated keychain so login-keychain ACL never blocks menu-bar TLS.
    private static var tlsKeychainURL: URL { supportDir.appendingPathComponent("tls.keychain-db") }
    nonisolated(unsafe) private static var tlsKeychain: SecKeychain?

    /// Mid-session Wi‑Fi / interface change: if primary LAN IP left SAN, drop cache + files and regen.
    /// Returns true when a new identity was generated (HTTPS listener should re-attach).
    @discardableResult
    static func revalidateForCurrentLAN() -> Bool {
        let primary = LANDetector.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty, primary != "127.0.0.1" else {
            return false
        }
        // Already ready and SAN covers primary → no-op
        lock.lock()
        let ready = cachedReady && cachedIdentity != nil
        lock.unlock()
        if ready, !shouldRegenerateForLANIP() {
            return false
        }
        if shouldRegenerateForLANIP() || !ready {
            MagicLog.server("LAN TLS revalidate: primary=\(primary) regen (network change or not ready)")
            deleteCertFiles()
            return ensureIdentity() != nil
        }
        return false
    }

    /// Ensure identity exists (generate via openssl if needed) and return it.
    /// Self-heal: if p12 exists but primary LAN IP is missing from SAN, delete cert files and regenerate.
    @discardableResult
    static func ensureIdentity() -> SecIdentity? {
        lock.lock()
        if cachedIdentity != nil, cachedReady {
            // Still verify SAN covers current primary (leave-home Wi‑Fi / DHCP)
            lock.unlock()
            if shouldRegenerateForLANIP() {
                MagicLog.server("LAN TLS cached identity stale for current LAN — regen")
                deleteCertFiles()
                // fall through to generate path
            } else {
                lock.lock()
                if let id2 = cachedIdentity, cachedReady {
                    lock.unlock()
                    return id2
                }
                lock.unlock()
            }
        } else {
            lock.unlock()
        }

        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: p12URL.path) {
                if shouldRegenerateForLANIP() {
                    MagicLog.server("LAN TLS SAN missing primary IP — regen (delete p12/pem/cer)")
                    deleteCertFiles()
                    try generateWithOpenSSL()
                    MagicLog.server("LAN TLS regen complete (SAN includes current private IPs)")
                }
            } else {
                try generateWithOpenSSL()
            }
            guard let id = importP12(from: p12URL) else {
                // Corrupt p12: force regen once
                MagicLog.server("LAN TLS p12 import failed — regen")
                deleteCertFiles()
                try generateWithOpenSSL()
                guard let id2 = importP12(from: p12URL) else {
                    setError("p12_import_failed")
                    return nil
                }
                lock.lock()
                cachedIdentity = id2
                cachedReady = true
                lastError = ""
                lock.unlock()
                MagicLog.server("LAN TLS identity ready after regen (https :\(httpsPort)) p12=\(p12URL.path)")
                return id2
            }
            lock.lock()
            cachedIdentity = id
            cachedReady = true
            lastError = ""
            lock.unlock()
            MagicLog.server("LAN TLS identity ready (https :\(httpsPort)) p12=\(p12URL.path)")
            return id
        } catch {
            setError(error.localizedDescription)
            MagicLog.server("LAN TLS cert failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// True when primary private LAN IP is set and not present in existing cert SAN.
    private static func shouldRegenerateForLANIP() -> Bool {
        let primary = LANDetector.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty, primary != "127.0.0.1" else {
            return false
        }
        guard let sanText = readExistingSANText() else {
            // No readable PEM/SAN — treat as mismatched so we heal
            MagicLog.server("LAN TLS cannot read SAN from existing cert — will regen")
            return true
        }
        // openssl -ext subjectAltName / -text: "IP Address:1.2.3.4" (or compact "IP:1.2.3.4")
        if sanText.contains("IP Address:\(primary)") || sanText.contains("IP:\(primary)") {
            return false
        }
        MagicLog.server("LAN TLS primary IP \(primary) not in SAN — will regen")
        return true
    }

    /// Read SAN extension text from on-disk PEM (preferred) or fail.
    private static func readExistingSANText() -> String? {
        let openssl = resolveOpenSSL()
        guard !openssl.isEmpty else { return nil }
        let certPath: String
        if FileManager.default.fileExists(atPath: pemCertURL.path) {
            certPath = pemCertURL.path
        } else if FileManager.default.fileExists(atPath: cerURL.path) {
            certPath = cerURL.path
        } else {
            return nil
        }
        // Prefer subjectAltName ext; fall back to full text
        if let out = try? runCapture(openssl, args: [
            "x509", "-in", certPath, "-noout", "-ext", "subjectAltName",
        ]), !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return out
        }
        return try? runCapture(openssl, args: [
            "x509", "-in", certPath, "-noout", "-text",
        ])
    }

    private static func deleteCertFiles() {
        for u in [p12URL, cerURL, pemCertURL, pemKeyURL] {
            try? FileManager.default.removeItem(at: u)
        }
        // Drop dedicated TLS keychain so next import is clean (new SAN)
        if let kc = tlsKeychain {
            SecKeychainDelete(kc)
            tlsKeychain = nil
        }
        try? FileManager.default.removeItem(at: tlsKeychainURL)
        lock.lock()
        cachedIdentity = nil
        cachedReady = false
        lock.unlock()
    }

    /// Ensure file keychain exists, unlocked, no auto-lock (via /usr/bin/security — reliable on modern macOS).
    private static func prepareTLSKeychainFile() -> String? {
        let path = tlsKeychainURL.path
        let sec = "/usr/bin/security"
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try run(sec, args: ["create-keychain", "-p", p12Pass, path])
            } catch {
                MagicLog.server("create-keychain: \(error.localizedDescription)")
            }
        }
        do {
            try run(sec, args: ["unlock-keychain", "-p", p12Pass, path])
            // -u = no lock on sleep; -l 0 / no lock interval via set-keychain-settings
            try run(sec, args: ["set-keychain-settings", "-u", path])
        } catch {
            MagicLog.server("unlock-keychain: \(error.localizedDescription)")
            return nil
        }
        // Open SecKeychain ref for SecPKCS12Import target
        var kc: SecKeychain?
        let openSt = path.withCString { SecKeychainOpen($0, &kc) }
        if openSt != errSecSuccess {
            MagicLog.server("SecKeychainOpen status=\(openSt)")
        }
        tlsKeychain = kc
        return path
    }

    /// NWParameters with TLS local identity for server listener.
    static func makeTLSParameters() -> NWParameters? {
        guard let identity = ensureIdentity() else { return nil }
        guard let secIdentity = sec_identity_create(identity) else {
            setError("sec_identity_create_failed")
            return nil
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        // Server: do not require client certs
        sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, false)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // Fast Open + TLS often breaks ClientHello on local listeners
        tcp.enableFastOpen = false
        tcp.connectionTimeout = 10

        let params = NWParameters(tls: tls, tcp: tcp)
        params.acceptLocalOnly = false
        return params
    }

    static func plainTCPParameters() -> NWParameters {
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableFastOpen = true
            tcp.connectionTimeout = 10
        }
        params.acceptLocalOnly = false
        return params
    }

    // MARK: - OpenSSL generate

    private static func generateWithOpenSSL() throws {
        let openssl = resolveOpenSSL()
        guard !openssl.isEmpty else {
            throw NSError(domain: "LANCert", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "openssl_not_found"
            ])
        }

        let ips = collectSANIPs()
        let san = buildSAN(ips: ips)
        let confURL = supportDir.appendingPathComponent("openssl-san.cnf")
        let conf = """
        [req]
        default_bits = 2048
        prompt = no
        default_md = sha256
        distinguished_name = dn
        x509_extensions = v3_req

        [dn]
        CN = \(certCommonName)
        O = MagicPad
        OU = LAN

        [v3_req]
        basicConstraints = CA:FALSE
        keyUsage = digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = \(san)
        """
        try conf.write(to: confURL, atomically: true, encoding: .utf8)

        // Remove stale PEMs so regen is clean
        for u in [pemKeyURL, pemCertURL, p12URL, cerURL] {
            try? FileManager.default.removeItem(at: u)
        }

        try run(openssl, args: [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "825", "-nodes",
            "-keyout", pemKeyURL.path,
            "-out", pemCertURL.path,
            "-config", confURL.path,
            "-extensions", "v3_req",
        ])

        // macOS Security.framework / Network TLS: prefer classic PKCS#12 (3DES+SHA1).
        // OpenSSL 3 default AES-256 P12 often imports cert-only (0 identities) → TLS -9858.
        var p12Args = [
            "pkcs12", "-export",
            "-inkey", pemKeyURL.path,
            "-in", pemCertURL.path,
            "-out", p12URL.path,
            "-passout", "pass:\(p12Pass)",
            "-name", certCommonName,
            "-certpbe", "PBE-SHA1-3DES",
            "-keypbe", "PBE-SHA1-3DES",
            "-macalg", "sha1",
        ]
        // Homebrew OpenSSL 3 may need -legacy for 3DES bags
        if openssl.contains("homebrew") || openssl.contains("/opt/") || openssl.contains("/usr/local/") {
            p12Args.append("-legacy")
        }
        do {
            try run(openssl, args: p12Args)
        } catch {
            // Fallback: plain export without legacy flags (system /usr/bin/openssl)
            MagicLog.server("LAN TLS p12 legacy export failed, retry plain: \(error.localizedDescription)")
            try run(openssl, args: [
                "pkcs12", "-export",
                "-inkey", pemKeyURL.path,
                "-in", pemCertURL.path,
                "-out", p12URL.path,
                "-passout", "pass:\(p12Pass)",
                "-name", certCommonName,
            ])
        }

        // DER .cer for optional phone install
        try run(openssl, args: [
            "x509", "-in", pemCertURL.path, "-outform", "DER", "-out", cerURL.path,
        ])

        MagicLog.server("LAN TLS generated SAN=\(san)")
    }

    private static func collectSANIPs() -> [String] {
        var set: [String] = ["127.0.0.1"]
        let primary = LANDetector.ip
        if !primary.isEmpty, primary != "127.0.0.1" { set.append(primary) }
        for ip in LANDetector.allPrivateIPs where !set.contains(ip) {
            set.append(ip)
        }
        return set
    }

    private static func buildSAN(ips: [String]) -> String {
        var parts = ["DNS:localhost", "DNS:*.local", "DNS:magicpad.local"]
        for ip in ips {
            parts.append("IP:\(ip)")
        }
        return parts.joined(separator: ",")
    }

    private static func resolveOpenSSL() -> String {
        let candidates = [
            "/opt/homebrew/bin/openssl",
            "/usr/local/bin/openssl",
            "/usr/bin/openssl",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return ""
    }

    private static func run(_ exe: String, args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "LANCert", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "openssl failed: \(err.prefix(200))"
            ])
        }
    }

    /// Run openssl and return combined stdout (for SAN inspection). Nil/empty on failure.
    private static func runCapture(_ exe: String, args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "LANCert", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "openssl capture failed: \(err.prefix(200))"
            ])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Import PKCS#12 into dedicated unlocked keychain; keep SecIdentity from import result
    /// (SecItemCopyMatching identities crash BoringSSL SecIdentityCopyPrivateKey on some macOS).
    private static func importP12(from url: URL) -> SecIdentity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard prepareTLSKeychainFile() != nil else {
            MagicLog.server("TLS keychain unavailable")
            return nil
        }

        var access: SecAccess?
        _ = SecAccessCreate("MagicPad LAN TLS" as CFString, nil, &access)

        // Prefer import into dedicated keychain (no login-keychain UI / ACL)
        if let id = pkcs12Import(data: data, access: access, keychain: tlsKeychain) {
            MagicLog.server("LAN TLS private key OK (SecPKCS12Import → dedicated keychain)")
            return id
        }

        // Fallback: temporarily set default keychain to ours, import without explicit keychain ref
        var previousDefault: SecKeychain?
        _ = SecKeychainCopyDefault(&previousDefault)
        if let kc = tlsKeychain {
            _ = SecKeychainSetDefault(kc)
        }
        defer {
            if let previousDefault {
                _ = SecKeychainSetDefault(previousDefault)
            }
        }
        if let id = pkcs12Import(data: data, access: access, keychain: nil) {
            MagicLog.server("LAN TLS private key OK (SecPKCS12Import → default=dedicated)")
            return id
        }

        MagicLog.server("SecPKCS12Import failed all strategies")
        return nil
    }

    private static func pkcs12Import(data: Data, access: SecAccess?, keychain: SecKeychain?) -> SecIdentity? {
        var opts: [String: Any] = [kSecImportExportPassphrase as String: p12Pass]
        if let access { opts[kSecImportExportAccess as String] = access }
        if let keychain { opts[kSecImportExportKeychain as String] = keychain }
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, opts as CFDictionary, &items)
        guard status == errSecSuccess, let arr = items as? [[String: Any]], let first = arr.first else {
            MagicLog.server("SecPKCS12Import status=\(status) keychain=\(keychain != nil)")
            return nil
        }
        guard let anyId = first[kSecImportItemIdentity as String] else {
            MagicLog.server("SecPKCS12Import: no identity in bag")
            return nil
        }
        let identity = anyId as! SecIdentity
        var privateKey: SecKey?
        let keySt = SecIdentityCopyPrivateKey(identity, &privateKey)
        if keySt != errSecSuccess || privateKey == nil {
            MagicLog.server("SecIdentityCopyPrivateKey status=\(keySt) — identity unusable")
            return nil
        }
        // Confirm key attrs once on this thread (helps surface bad identities early)
        _ = SecKeyCopyAttributes(privateKey!)
        return identity
    }

    private static func setError(_ msg: String) {
        lock.lock()
        lastError = msg
        cachedReady = false
        cachedIdentity = nil
        lock.unlock()
    }
}
