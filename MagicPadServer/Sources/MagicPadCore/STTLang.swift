// STTLang.swift
// Cycle 24: STT JSON lang allowlist lives in Core (MP-12 / MP-18).
// zh-CN / en-US / ja-JP. Anything else → zh-CN. No cloud locale guess.

import Foundation

public enum STTLang {
    public static let allowed: Set<String> = ["zh-CN", "en-US", "ja-JP"]
    public static let fallback = "zh-CN"

    public static func parse(_ raw: String?) -> String {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if allowed.contains(key) { return key }
        return fallback
    }
}
