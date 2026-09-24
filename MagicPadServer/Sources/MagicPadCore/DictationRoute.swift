// DictationRoute.swift
// Pure routing for on-device Whisper vs Apple Speech. No audio, no network, no LLM.

import Foundation

public enum DictationRoute {
    /// Whisper already ran and returned no words (`reason == "empty"`).
    /// That is a result, not an engine failure. Do not hand the clip to SFSpeech:
    /// Apple may run in the cloud, and a silence clip can come back as text.
    public static func shouldFallbackToApple(ok: Bool, reason: String?) -> Bool {
        if ok { return false }
        let r = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if r == "empty" { return false }
        return true
    }

    /// POST /stt `engine`. On-device Apple Speech is not Whisper ANE.
    /// Anything that did not actually run Whisper is reported as `apple`.
    public static func reportedEngine(_ actual: String?) -> String {
        let e = (actual ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return e == "whisper" ? "whisper" : "apple"
    }
}
