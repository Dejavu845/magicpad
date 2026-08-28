// KeyProtocol.swift
// Pure key-action helpers (no AppKit) — clamp, count parse, action allowlist, type-text clamp.
// Used by WebSocketServer handleKeyAction / handleTypeText and unit-tested via MagicPadCore.

import Foundation

/// Pure key-inject protocol helpers (no CGEvent / no menu bar).
public enum KeyProtocol {
    public static let minCount = 1
    public static let maxCount = 200
    /// Max graphemes for a single `{ "type":"type", "text":… }` payload (keySerial safety).
    public static let maxTypeChars = 2000

    /// Canonical actions accepted by `EventInjector.injectEditAction`.
    /// Aliases are mapped via `canonicalizeAction` before allowlist check.
    public static let allowedActions: Set<String> = [
        "backspace",
        "wordBackspace",
        "wordForwardDelete",
        "wordLeft",
        "wordRight",
        "selectLeft",
        "selectRight",
        "selectWordLeft",
        "selectWordRight",
        "selectUp",
        "selectDown",
        "selectHome",
        "selectEnd",
        "selectPageUp",
        "selectPageDown",
        "lineStart",
        "lineEnd",
        "selectLineStart",
        "selectLineEnd",
        "lineBackspace",
        "lineForwardDelete",
        "clearField",
        "selectAll",
        "left",
        "right",
        "up",
        "down",
        "enter",
        "unstick",
        "delete",
        "forwardDelete",
        "escape",
        "tab",
        "home",
        "end",
        "pageUp",
        "pageDown",
        "cut",
        "copy",
        "paste",
        "undo",
        "redo",
        "showDesktop",
        "missionControl",
        "launchpad",
        "notificationCenter",
        "lookUp",
        "openAccessibility",
    ]

    /// Clamp key repeat count into `1…200` (0/negative → 1, >200 → 200).
    public static func clampKeyCount(_ count: Int) -> Int {
        max(minCount, min(maxCount, count))
    }

    /// Normalize action string: trim + casefold (lowercased). Empty means invalid.
    public static func normalizeAction(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Map client aliases / casefold forms to canonical action names.
    /// Aliases: return|ret → enter; desktop → showDesktop; mission → missionControl;
    /// releaseModifiers → unstick; bs → backspace; del|deleteForward|fwd|fwdDel → forwardDelete;
    /// esc → escape; wb|altbs → wordBackspace; eol → end; pgup|pageup → pageUp; pgdn|pagedown → pageDown;
    /// wleft|altleft|optleft → wordLeft; wright|altright|optright → wordRight;
    /// sleft|shiftleft|sell → selectLeft; sright|shiftright|ser → selectRight;
    /// swleft|selwleft|shiftwordleft|shiftoptleft → selectWordLeft;
    /// swright|selwright|shiftwordright|shiftoptright → selectWordRight;
    /// sup|shiftup|selu → selectUp; sdn|shiftdown|seld → selectDown;
    /// shome|shifthome|selhome → selectHome; send|shiftend|selend → selectEnd;
    /// spup|shiftpgup|selpgup → selectPageUp; spdn|shiftpgdn|selpgdn → selectPageDown;
    /// rdo|shiftundo|cmdshiftz → redo;
    /// lstart|cmdleft|bol|sol → lineStart; lend|cmdright|softend → lineEnd (eol still → end);
    /// lbs|cmdbs|deletelinestart|dellinestart → lineBackspace;
    /// lfd|cmdfwd|deletelineend|dellineend → lineForwardDelete;
    /// slstart|sellinestart|cmdshiftleft|shiftcmdleft → selectLineStart;
    /// slend|sellineend|cmdshiftright|shiftcmdright → selectLineEnd.
    /// Also restores camelCase after casefold (clearfield → clearField, etc.).
    public static func canonicalizeAction(_ action: String) -> String {
        // Accept both pre-normalized (lowercased) and raw mixed-case callers.
        let a = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch a {
        case "return", "ret": return "enter"
        case "desktop": return "showDesktop"
        case "mission": return "missionControl"
        case "notify", "nc", "notification", "notificationcentre": return "notificationCenter"
        case "lookup", "define", "dict": return "lookUp"
        case "ax", "accessibility", "openax": return "openAccessibility"
        case "releasemodifiers": return "unstick"
        case "bs": return "backspace"
        case "del", "deleteforward", "fwd", "fwddel": return "forwardDelete"
        case "esc": return "escape"
        case "wb", "altbs": return "wordBackspace"
        case "wfd", "altfwd", "optfwd", "wordfwd", "altforwarddelete": return "wordForwardDelete"
        case "wleft", "altleft", "optleft": return "wordLeft"
        case "wright", "altright", "optright": return "wordRight"
        case "sleft", "shiftleft", "sell": return "selectLeft"
        case "sright", "shiftright", "ser": return "selectRight"
        case "swleft", "selwleft", "shiftwordleft", "shiftoptleft": return "selectWordLeft"
        case "swright", "selwright", "shiftwordright", "shiftoptright": return "selectWordRight"
        case "sup", "shiftup", "selu": return "selectUp"
        case "sdn", "shiftdown", "seld": return "selectDown"
        case "shome", "shifthome", "selhome": return "selectHome"
        case "send", "shiftend", "selend": return "selectEnd"
        case "spup", "shiftpgup", "selpgup": return "selectPageUp"
        case "spdn", "shiftpgdn", "selpgdn": return "selectPageDown"
        case "rdo", "shiftundo", "cmdshiftz": return "redo"
        case "lstart", "cmdleft", "bol", "sol": return "lineStart"
        case "lend", "cmdright", "softend": return "lineEnd"
        case "lbs", "cmdbs", "deletelinestart", "dellinestart": return "lineBackspace"
        case "lfd", "cmdfwd", "deletelineend", "dellineend": return "lineForwardDelete"
        case "slstart", "sellinestart", "cmdshiftleft", "shiftcmdleft": return "selectLineStart"
        case "slend", "sellineend", "cmdshiftright", "shiftcmdright": return "selectLineEnd"
        case "eol": return "end"
        case "pgup", "pageup": return "pageUp"
        case "pgdn", "pagedown": return "pageDown"
        // camelCase restore after casefold
        case "clearfield": return "clearField"
        case "wordbackspace": return "wordBackspace"
        case "wordforwarddelete": return "wordForwardDelete"
        case "wordleft": return "wordLeft"
        case "wordright": return "wordRight"
        case "selectleft": return "selectLeft"
        case "selectright": return "selectRight"
        case "selectwordleft": return "selectWordLeft"
        case "selectwordright": return "selectWordRight"
        case "selectup": return "selectUp"
        case "selectdown": return "selectDown"
        case "selecthome": return "selectHome"
        case "selectend": return "selectEnd"
        case "selectpageup": return "selectPageUp"
        case "selectpagedown": return "selectPageDown"
        case "linestart": return "lineStart"
        case "lineend": return "lineEnd"
        case "linebackspace": return "lineBackspace"
        case "lineforwarddelete": return "lineForwardDelete"
        case "selectlinestart": return "selectLineStart"
        case "selectlineend": return "selectLineEnd"
        case "selectall": return "selectAll"
        case "forwarddelete": return "forwardDelete"
        case "showdesktop": return "showDesktop"
        case "missioncontrol": return "missionControl"
        case "notificationcenter": return "notificationCenter"
        case "openaccessibility": return "openAccessibility"
        default: return a
        }
    }

    public static func isAllowedAction(_ action: String) -> Bool {
        let a = canonicalizeAction(normalizeAction(action))
        guard !a.isEmpty else { return false }
        return allowedActions.contains(a)
    }

    // MARK: - Type text clamp

    /// Result of clamping a type-text payload.
    public struct ClampedTypeText: Equatable, Sendable {
        public let text: String
        /// true when input was empty (after no further trim — raw empty)
        public let empty: Bool
        /// true when input exceeded `maxTypeChars` and was truncated
        public let truncated: Bool
        /// Protocol reason: `empty_type` | `type` | `type_truncated`
        public let reason: String

        public init(text: String, empty: Bool, truncated: Bool, reason: String) {
            self.text = text
            self.empty = empty
            self.truncated = truncated
            self.reason = reason
        }
    }

    /// Clamp type payload: empty → empty_type; oversize → prefix + type_truncated; else type.
    public static func clampTypeText(_ raw: String) -> ClampedTypeText {
        if raw.isEmpty {
            return ClampedTypeText(text: "", empty: true, truncated: false, reason: "empty_type")
        }
        if raw.count > maxTypeChars {
            let clipped = String(raw.prefix(maxTypeChars))
            return ClampedTypeText(text: clipped, empty: false, truncated: true, reason: "type_truncated")
        }
        return ClampedTypeText(text: raw, empty: false, truncated: false, reason: "type")
    }

    /// Parse type payload from WS JSON (pure; no inject).
    /// - String `text` → `clampTypeText` (empty_type / type / type_truncated)
    /// - missing key or null → empty_type
    /// - non-string present (number/bool/array/dict) → bad_type (empty, no inject)
    public static func parseType(from json: [String: Any]) -> ClampedTypeText {
        guard let raw = json["text"] else {
            return ClampedTypeText(text: "", empty: true, truncated: false, reason: "empty_type")
        }
        if raw is NSNull {
            return ClampedTypeText(text: "", empty: true, truncated: false, reason: "empty_type")
        }
        if let s = raw as? String {
            return clampTypeText(s)
        }
        // Non-string present: refuse rather than coerce (malformed hardening)
        return ClampedTypeText(text: "", empty: true, truncated: false, reason: "bad_type")
    }

    /// True when `value` is a JSON/Swift boolean (not integer 0/1).
    /// Do NOT use `value is Bool` — NSNumber(0)/NSNumber(1) bridge to Bool.
    public static func isJSONBoolean(_ value: Any) -> Bool {
        if type(of: value) == Bool.self { return true }
        // JSONSerialization true/false → __NSCFBoolean (NSNumber subclass), distinct from __NSCFNumber
        if let n = value as? NSNumber {
            return type(of: n) == type(of: NSNumber(value: true))
        }
        return false
    }

    /// Parse a numeric field that may be Int, Double, or NSNumber (JSONSerialization).
    /// Rejects Bool / CFBoolean, arrays, dicts, non-int strings.
    public static func intFromJSONValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        // Reject pure Bool + JSON CFBoolean; keep NSNumber integers 0/1
        if isJSONBoolean(value) { return nil }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let f = value as? Float { return Int(f) }
        if let n = value as? NSNumber {
            return n.intValue
        }
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let i = Int(t) else { return nil }
            return i
        }
        return nil
    }

    /// Whether a present JSON value is a non-numeric count (bool/array/dict/non-int string).
    /// Null is treated as absent (not malformed).
    public static func isMalformedCountValue(_ value: Any) -> Bool {
        if value is NSNull { return false }
        return intFromJSONValue(value) == nil
    }

    /// Result of strict count parse (OPT-14).
    public struct ParsedCount: Equatable, Sendable {
        public let value: Int
        /// false when a present count/repeat field is non-numeric
        public let ok: Bool
        /// `bad_count` when !ok; empty when ok
        public let reason: String

        public init(value: Int, ok: Bool, reason: String = "") {
            self.value = value
            self.ok = ok
            self.reason = reason
        }

        public static let `default` = ParsedCount(value: KeyProtocol.minCount, ok: true, reason: "")
    }

    /// Strict count parse: missing/null count+repeat → default 1;
    /// present non-numeric (bool/array/dict/non-int string) → bad_count;
    /// valid Int/Double/string-int → clamp 1…200.
    public static func parseCount(from json: [String: Any]) -> ParsedCount {
        if let raw = json["count"] {
            if raw is NSNull {
                // null count → fall through to repeat
            } else if isMalformedCountValue(raw) {
                return ParsedCount(value: minCount, ok: false, reason: "bad_count")
            } else if let c = intFromJSONValue(raw) {
                return ParsedCount(value: clampKeyCount(c), ok: true, reason: "")
            }
        }
        if let raw = json["repeat"] {
            if raw is NSNull {
                return .default
            }
            if isMalformedCountValue(raw) {
                return ParsedCount(value: minCount, ok: false, reason: "bad_count")
            }
            if let c = intFromJSONValue(raw) {
                return ParsedCount(value: clampKeyCount(c), ok: true, reason: "")
            }
        }
        return .default
    }

    /// Normalize count from WS JSON: prefer `count` (Int/Double), else `repeat`.
    /// Always returns a clamped value in `1…200` (default 1).
    /// Note: malformed present values are treated as missing here; use `parseCount` for rejection.
    public static func normalizeCount(from json: [String: Any]) -> Int {
        let p = parseCount(from: json)
        return p.ok ? p.value : minCount
    }

    /// Direct normalize from optional count / repeat values (unit-test friendly).
    public static func normalizeCount(count: Any?, `repeat` repeatValue: Any? = nil) -> Int {
        var json: [String: Any] = [:]
        if let count { json["count"] = count }
        if let repeatValue { json["repeat"] = repeatValue }
        return normalizeCount(from: json)
    }

    public struct ParsedKey: Equatable, Sendable {
        /// Canonical action name (aliases already mapped). Empty when empty_action / bad_action.
        public let action: String
        public let count: Int
        /// false when action is non-empty but not on the allowlist, or empty/bad/bad_count
        public let allowed: Bool
        /// Protocol reason: `empty_action` | `bad_action` | `bad_count` | `unknown_action` | canonical action when allowed
        public let reason: String

        public init(action: String, count: Int, allowed: Bool, reason: String) {
            self.action = action
            self.count = count
            self.allowed = allowed
            self.reason = reason
        }

        /// Missing / null / whitespace action — no inject.
        public var isEmptyAction: Bool { reason == "empty_action" }
        /// Non-string action field (number/bool/array/dict) — no inject.
        public var isBadAction: Bool { reason == "bad_action" }
        /// Present non-numeric count/repeat — no inject (OPT-14).
        public var isBadCount: Bool { reason == "bad_count" }
        /// empty_action / bad_action / bad_count — handleKeyAction must not inject.
        public var shouldReject: Bool { isEmptyAction || isBadAction || isBadCount }
    }

    /// Parse key JSON (pure; no inject). Malformed-hardening mirror of `parseType`:
    /// - String `action` → normalize + canonicalize + clamp count; allowlist → allowed
    /// - missing key or null or whitespace-only → `empty_action` (no inject)
    /// - non-string present (number/bool/array/dict) → `bad_action` (no inject; never coerce via `as? String`)
    /// - present non-numeric count/repeat → `bad_count` (no inject)
    /// - non-empty unknown string → allowed=false, reason=`unknown_action`
    public static func parseKey(from json: [String: Any]) -> ParsedKey {
        guard let rawVal = json["action"] else {
            return ParsedKey(action: "", count: minCount, allowed: false, reason: "empty_action")
        }
        if rawVal is NSNull {
            return ParsedKey(action: "", count: minCount, allowed: false, reason: "empty_action")
        }
        guard let s = rawVal as? String else {
            // Non-string present: refuse rather than coerce (OPT-11)
            return ParsedKey(action: "", count: minCount, allowed: false, reason: "bad_action")
        }
        let raw = normalizeAction(s)
        guard !raw.isEmpty else {
            return ParsedKey(action: "", count: minCount, allowed: false, reason: "empty_action")
        }
        let action = canonicalizeAction(raw)
        let countParsed = parseCount(from: json)
        if !countParsed.ok {
            return ParsedKey(action: action, count: minCount, allowed: false, reason: "bad_count")
        }
        let count = countParsed.value
        let allowed = allowedActions.contains(action)
        let reason = allowed ? action : "unknown_action"
        return ParsedKey(action: action, count: count, allowed: allowed, reason: reason)
    }
}
