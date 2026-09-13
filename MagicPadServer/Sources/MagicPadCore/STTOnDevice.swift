// STTOnDevice.swift
// Cycle 25: STT JSON onDevice lives in Core (MP-12 / MP-18).
// JSON bool only. Missing / non-bool → true (on-device). No cloud fallback.

import Foundation

public enum STTOnDevice {
    public static let jsonField = "onDevice"
    public static let defaultOn = true

    public static func parse(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        return defaultOn
    }
}
