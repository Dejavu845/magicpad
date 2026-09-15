// PairingRuntime.swift
// Menu-generated PIN. Default off. Never a /health key, never a QR query.

import Foundation
import MagicPadCore

enum PairingRuntime: Sendable {
    static let defaultsKey = "magicpad.pairingPin"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _code: String?

    static var code: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _code
        }
        set {
            lock.lock()
            let trimmed = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            _code = trimmed.isEmpty ? nil : trimmed
            lock.unlock()
        }
    }

    static func activeConfigured() -> String? {
        PairingToken.mergeConfigured(PairingToken.configured(), code)
    }

    static func required() -> Bool {
        activeConfigured() != nil
    }

    static func allows(_ provided: String?) -> Bool {
        PairingToken.allows(provided, configured: activeConfigured())
    }

    static func loadFromDefaults() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        code = raw
    }

    static func persist(_ value: String?) {
        code = value
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
