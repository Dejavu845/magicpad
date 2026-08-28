// KeyProtocolTests.swift — pure key-protocol unit tests (no AppKit, no LLM)

import XCTest
@testable import MagicPadCore

final class KeyProtocolTests: XCTestCase {

    // MARK: - clampKeyCount

    func testClampZeroBecomesOne() {
        XCTAssertEqual(KeyProtocol.clampKeyCount(0), 1)
    }

    func testClamp201Becomes200() {
        XCTAssertEqual(KeyProtocol.clampKeyCount(201), 200)
    }

    func testClampNegativeBecomesOne() {
        XCTAssertEqual(KeyProtocol.clampKeyCount(-1), 1)
        XCTAssertEqual(KeyProtocol.clampKeyCount(-99), 1)
    }

    func testClampPassthroughInRange() {
        XCTAssertEqual(KeyProtocol.clampKeyCount(1), 1)
        XCTAssertEqual(KeyProtocol.clampKeyCount(40), 40)
        XCTAssertEqual(KeyProtocol.clampKeyCount(200), 200)
    }

    // MARK: - normalizeCount (Int / Double / repeat)

    func testNormalizeCountInt() {
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": 7]), 7)
        XCTAssertEqual(KeyProtocol.normalizeCount(count: 12), 12)
    }

    func testNormalizeCountDouble() {
        // Int(3.9) → 3; then clamp
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": 3.9]), 3)
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": 0.2]), 1) // clamped
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": 250.8]), 200)
        XCTAssertEqual(KeyProtocol.normalizeCount(count: 5.0), 5)
    }

    func testNormalizeCountRepeat() {
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["repeat": 9]), 9)
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["repeat": 0]), 1)
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["repeat": 201]), 200)
        XCTAssertEqual(KeyProtocol.normalizeCount(count: nil, repeat: 4), 4)
    }

    func testNormalizeCountPrefersCountOverRepeat() {
        XCTAssertEqual(
            KeyProtocol.normalizeCount(from: ["count": 2, "repeat": 99]),
            2
        )
    }

    func testNormalizeCountDefaultOne() {
        XCTAssertEqual(KeyProtocol.normalizeCount(from: [:]), 1)
        XCTAssertEqual(KeyProtocol.normalizeCount(count: nil, repeat: nil), 1)
    }

    func testNormalizeCountNegativeAndOversize() {
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": -3]), 1)
        XCTAssertEqual(KeyProtocol.normalizeCount(from: ["count": 999]), 200)
    }

    // MARK: - action allowlist

    func testKnownEditActionsAllowed() {
        let known = [
            "backspace", "wordBackspace", "clearField", "selectAll",
            "left", "right", "up", "down", "enter", "unstick",
            "delete", "paste", "launchpad", "releaseModifiers",
        ]
        for a in known {
            XCTAssertTrue(KeyProtocol.isAllowedAction(a), "expected allowed: \(a)")
        }
    }

    func testUnknownActionRejected() {
        XCTAssertFalse(KeyProtocol.isAllowedAction(""))
        XCTAssertFalse(KeyProtocol.isAllowedAction("hack"))
        XCTAssertFalse(KeyProtocol.isAllowedAction("rm"))
        XCTAssertFalse(KeyProtocol.isAllowedAction("shell"))
        XCTAssertFalse(KeyProtocol.isAllowedAction("unknown_action"))
    }

    func testParseKeyUnknownFlagged() {
        let p = KeyProtocol.parseKey(from: ["action": "explode", "count": 3])
        XCTAssertEqual(p.action, "explode")
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.allowed, false)
        XCTAssertEqual(p.reason, "unknown_action")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeyEmptyAction() {
        let empty = KeyProtocol.parseKey(from: ["action": ""])
        XCTAssertEqual(empty.reason, "empty_action")
        XCTAssertTrue(empty.shouldReject)
        XCTAssertFalse(empty.allowed)
        let ws = KeyProtocol.parseKey(from: ["action": "   "])
        XCTAssertEqual(ws.reason, "empty_action")
        XCTAssertTrue(ws.shouldReject)
        let missing = KeyProtocol.parseKey(from: [:])
        XCTAssertEqual(missing.reason, "empty_action")
        XCTAssertTrue(missing.shouldReject)
    }

    func testParseKeyBackspaceHappyPath() {
        let p = KeyProtocol.parseKey(from: ["action": "backspace", "count": 40])
        XCTAssertEqual(
            p,
            KeyProtocol.ParsedKey(action: "backspace", count: 40, allowed: true, reason: "backspace")
        )
    }

    func testParseKeyTrimsAction() {
        let p = KeyProtocol.parseKey(from: ["action": "  clearField  ", "repeat": 1])
        XCTAssertEqual(p.action, "clearField")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.reason, "clearField")
    }

    // MARK: - canonicalizeAction (OPT-04)

    func testCanonicalizeReturnToEnter() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("return"), "enter")
    }

    func testCanonicalizeDesktopToShowDesktop() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("desktop"), "showDesktop")
    }

    func testCanonicalizeMissionToMissionControl() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("mission"), "missionControl")
    }

    func testCanonicalizeNotifyAndLookUp() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("notify"), "notificationCenter")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("nc"), "notificationCenter")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lookup"), "lookUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("define"), "lookUp")
        XCTAssertTrue(KeyProtocol.isAllowedAction("notificationCenter"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("lookUp"))
    }

    func testCanonicalizeAxToOpenAccessibility() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("ax"), "openAccessibility")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("openAccessibility"), "openAccessibility")
        let p = KeyProtocol.parseKey(from: ["action": "ax"])
        XCTAssertEqual(p.action, "openAccessibility")
        XCTAssertEqual(p.allowed, true)
    }

    func testCanonicalizeReleaseModifiersToUnstick() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("releaseModifiers"), "unstick")
    }

    func testCanonicalizePassthrough() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("backspace"), "backspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("enter"), "enter")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("unstick"), "unstick")
    }

    func testParseKeyReturnAliasCanonical() {
        let p = KeyProtocol.parseKey(from: ["action": "return", "count": 1])
        XCTAssertEqual(p.action, "enter")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "enter")
    }

    func testParseKeyDesktopAliasCanonical() {
        let p = KeyProtocol.parseKey(from: ["action": "desktop"])
        XCTAssertEqual(p.action, "showDesktop")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyMissionAliasCanonical() {
        let p = KeyProtocol.parseKey(from: ["action": "mission"])
        XCTAssertEqual(p.action, "missionControl")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyReleaseModifiersAliasCanonical() {
        let p = KeyProtocol.parseKey(from: ["action": "releaseModifiers"])
        XCTAssertEqual(p.action, "unstick")
        XCTAssertEqual(p.allowed, true)
    }

    func testIsAllowedActionAliases() {
        XCTAssertTrue(KeyProtocol.isAllowedAction("return"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("desktop"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("mission"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("releaseModifiers"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("  return  "))
    }

    // MARK: - casefold + expanded aliases (OPT-05)

    func testNormalizeActionCasefolds() {
        XCTAssertEqual(KeyProtocol.normalizeAction("  Backspace  "), "backspace")
        XCTAssertEqual(KeyProtocol.normalizeAction("RETURN"), "return")
        XCTAssertEqual(KeyProtocol.normalizeAction("ClearField"), "clearfield")
        XCTAssertEqual(KeyProtocol.normalizeAction("BS"), "bs")
        XCTAssertEqual(KeyProtocol.normalizeAction("ESC"), "esc")
    }

    func testCanonicalizeNewAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("bs"), "backspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("BS"), "backspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("del"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("deleteForward"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("esc"), "escape")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("ESC"), "escape")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("ret"), "enter")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("RET"), "enter")
    }

    func testParseKeyCasefoldBackspace() {
        let p = KeyProtocol.parseKey(from: ["action": "Backspace", "count": 2])
        XCTAssertEqual(p.action, "backspace")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
    }

    func testParseKeyCasefoldRETURN() {
        let p = KeyProtocol.parseKey(from: ["action": "RETURN", "count": 1])
        XCTAssertEqual(p.action, "enter")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyCasefoldClearField() {
        let p = KeyProtocol.parseKey(from: ["action": "ClearField"])
        XCTAssertEqual(p.action, "clearField")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyAliasBS() {
        let p = KeyProtocol.parseKey(from: ["action": "BS", "count": 3])
        XCTAssertEqual(p.action, "backspace")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 3)
    }

    func testParseKeyAliasESC() {
        let p = KeyProtocol.parseKey(from: ["action": "ESC"])
        XCTAssertEqual(p.action, "escape")
        XCTAssertEqual(p.allowed, true)
    }

    func testIsAllowedActionCasefold() {
        XCTAssertTrue(KeyProtocol.isAllowedAction("Backspace"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("RETURN"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ClearField"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("BS"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ESC"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ret"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("del"))
    }

    // MARK: - OPT-07 aliases (wb|altbs → wordBackspace; fwd|fwdDel → forwardDelete)

    func testCanonicalizeWordBackspaceAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wb"), "wordBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WB"), "wordBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altbs"), "wordBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altBs"), "wordBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wordBackspace"), "wordBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WordBackspace"), "wordBackspace")
    }

    func testCanonicalizeForwardDeleteAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("fwd"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("FWD"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("fwdDel"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("fwdDel"), "forwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("forwardDelete"), "forwardDelete")
    }

    func testParseKeyAliasWB() {
        let p = KeyProtocol.parseKey(from: ["action": "wb", "count": 2])
        XCTAssertEqual(p.action, "wordBackspace")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
    }

    func testParseKeyAliasAltBs() {
        let p = KeyProtocol.parseKey(from: ["action": "altbs", "count": 1])
        XCTAssertEqual(p.action, "wordBackspace")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyAliasFwd() {
        let p = KeyProtocol.parseKey(from: ["action": "fwd", "count": 3])
        XCTAssertEqual(p.action, "forwardDelete")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 3)
    }

    func testParseKeyAliasFwdDel() {
        let p = KeyProtocol.parseKey(from: ["action": "fwdDel"])
        XCTAssertEqual(p.action, "forwardDelete")
        XCTAssertEqual(p.allowed, true)
    }

    func testIsAllowedActionOPT07Aliases() {
        XCTAssertTrue(KeyProtocol.isAllowedAction("wb"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("altbs"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("fwd"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("fwdDel"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("wordBackspace"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("forwardDelete"))
    }

    // MARK: - clampTypeText (OPT-03)

    func testClampTypeTextEmpty() {
        let c = KeyProtocol.clampTypeText("")
        XCTAssertTrue(c.empty)
        XCTAssertFalse(c.truncated)
        XCTAssertEqual(c.text, "")
        XCTAssertEqual(c.reason, "empty_type")
    }

    func testClampTypeTextPassthrough() {
        let c = KeyProtocol.clampTypeText("Ab12测")
        XCTAssertFalse(c.empty)
        XCTAssertFalse(c.truncated)
        XCTAssertEqual(c.text, "Ab12测")
        XCTAssertEqual(c.reason, "type")
    }

    func testClampTypeTextExactMax() {
        let s = String(repeating: "a", count: KeyProtocol.maxTypeChars)
        let c = KeyProtocol.clampTypeText(s)
        XCTAssertFalse(c.empty)
        XCTAssertFalse(c.truncated)
        XCTAssertEqual(c.text.count, KeyProtocol.maxTypeChars)
        XCTAssertEqual(c.reason, "type")
    }

    func testClampTypeTextOversize() {
        let s = String(repeating: "x", count: KeyProtocol.maxTypeChars + 1)
        let c = KeyProtocol.clampTypeText(s)
        XCTAssertFalse(c.empty)
        XCTAssertTrue(c.truncated)
        XCTAssertEqual(c.text.count, KeyProtocol.maxTypeChars)
        XCTAssertEqual(c.reason, "type_truncated")
        XCTAssertEqual(c.text, String(repeating: "x", count: KeyProtocol.maxTypeChars))
    }

    func testClampTypeTextMaxTypeCharsConstant() {
        XCTAssertEqual(KeyProtocol.maxTypeChars, 2000)
    }

    // MARK: - parseType (OPT-09 malformed hardening)

    func testParseTypeHappyPath() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": "Ab12测"])
        XCTAssertFalse(c.empty)
        XCTAssertFalse(c.truncated)
        XCTAssertEqual(c.text, "Ab12测")
        XCTAssertEqual(c.reason, "type")
    }

    func testParseTypeMissingText() {
        let c = KeyProtocol.parseType(from: ["type": "type"])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.text, "")
        XCTAssertEqual(c.reason, "empty_type")
    }

    func testParseTypeNullText() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": NSNull()])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.reason, "empty_type")
    }

    func testParseTypeNumberText() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": 123])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.text, "")
        XCTAssertEqual(c.reason, "bad_type")
    }

    func testParseTypeBoolText() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": true])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.reason, "bad_type")
    }

    func testParseTypeArrayText() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": ["a", "b"]])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.reason, "bad_type")
    }

    func testParseTypeEmptyString() {
        let c = KeyProtocol.parseType(from: ["type": "type", "text": ""])
        XCTAssertTrue(c.empty)
        XCTAssertEqual(c.reason, "empty_type")
    }

    func testParseTypeTruncate() {
        let s = String(repeating: "z", count: KeyProtocol.maxTypeChars + 1)
        let c = KeyProtocol.parseType(from: ["type": "type", "text": s])
        XCTAssertFalse(c.empty)
        XCTAssertTrue(c.truncated)
        XCTAssertEqual(c.text.count, KeyProtocol.maxTypeChars)
        XCTAssertEqual(c.reason, "type_truncated")
    }

    // MARK: - nav keys tab/home/end (OPT-10)

    func testCanonicalizeEolToEnd() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("eol"), "end")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("EOL"), "end")
    }

    func testParseKeyTab() {
        let p = KeyProtocol.parseKey(from: ["action": "tab", "count": 1])
        XCTAssertEqual(p.action, "tab")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
    }

    func testParseKeyHome() {
        let p = KeyProtocol.parseKey(from: ["action": "home", "count": 2])
        XCTAssertEqual(p.action, "home")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
    }

    func testParseKeyEnd() {
        let p = KeyProtocol.parseKey(from: ["action": "end"])
        XCTAssertEqual(p.action, "end")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyAliasEol() {
        let p = KeyProtocol.parseKey(from: ["action": "eol", "count": 1])
        XCTAssertEqual(p.action, "end")
        XCTAssertEqual(p.allowed, true)
    }

    func testParseKeyCasefoldTabHomeEnd() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "Tab"]).action, "tab")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "HOME"]).action, "home")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "End"]).action, "end")
        XCTAssertTrue(KeyProtocol.isAllowedAction("Tab"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("home"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("eol"))
    }

    // MARK: - parseKey action-field pure parse (OPT-11 malformed hardening)

    func testParseKeyNullAction() {
        let p = KeyProtocol.parseKey(from: ["action": NSNull(), "count": 2])
        XCTAssertEqual(p.reason, "empty_action")
        XCTAssertTrue(p.isEmptyAction)
        XCTAssertTrue(p.shouldReject)
        XCTAssertEqual(p.action, "")
        XCTAssertFalse(p.allowed)
    }

    func testParseKeyNumberAction() {
        let p = KeyProtocol.parseKey(from: ["action": 123, "count": 2])
        XCTAssertEqual(p.reason, "bad_action")
        XCTAssertTrue(p.isBadAction)
        XCTAssertTrue(p.shouldReject)
        XCTAssertEqual(p.action, "")
        XCTAssertFalse(p.allowed)
        // Must not coerce number → "123" or empty_action
        XCTAssertNotEqual(p.reason, "empty_action")
    }

    func testParseKeyBoolAction() {
        let p = KeyProtocol.parseKey(from: ["action": true])
        XCTAssertEqual(p.reason, "bad_action")
        XCTAssertTrue(p.shouldReject)
    }

    func testParseKeyArrayAction() {
        let p = KeyProtocol.parseKey(from: ["action": ["backspace"]])
        XCTAssertEqual(p.reason, "bad_action")
        XCTAssertTrue(p.shouldReject)
    }

    func testParseKeyDictAction() {
        let p = KeyProtocol.parseKey(from: ["action": ["k": "v"]])
        XCTAssertEqual(p.reason, "bad_action")
        XCTAssertTrue(p.shouldReject)
    }

    func testParseKeyStringPathStillCanonicalAndClamp() {
        let p = KeyProtocol.parseKey(from: ["action": "  PageUp  ", "count": 250])
        XCTAssertEqual(p.action, "pageUp")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 200) // clamp
        XCTAssertEqual(p.reason, "pageUp")
        XCTAssertFalse(p.shouldReject)
    }

    // MARK: - nav keys pageUp/pageDown (OPT-12)

    func testCanonicalizePageUpAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pgup"), "pageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("PGUP"), "pageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pageup"), "pageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pageUp"), "pageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("PageUp"), "pageUp")
    }

    func testCanonicalizePageDownAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pgdn"), "pageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("PGDN"), "pageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pagedown"), "pageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("pageDown"), "pageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("PageDown"), "pageDown")
    }

    func testParseKeyPageUp() {
        let p = KeyProtocol.parseKey(from: ["action": "pageUp", "count": 1])
        XCTAssertEqual(p.action, "pageUp")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "pageUp")
    }

    func testParseKeyPageDown() {
        let p = KeyProtocol.parseKey(from: ["action": "pageDown", "count": 2])
        XCTAssertEqual(p.action, "pageDown")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "pageDown")
    }

    func testParseKeyAliasPgupPgdn() {
        let up = KeyProtocol.parseKey(from: ["action": "pgup", "count": 1])
        XCTAssertEqual(up.action, "pageUp")
        XCTAssertEqual(up.allowed, true)
        let down = KeyProtocol.parseKey(from: ["action": "pgdn"])
        XCTAssertEqual(down.action, "pageDown")
        XCTAssertEqual(down.allowed, true)
    }

    func testParseKeyCasefoldPageUpDown() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "PageUp"]).action, "pageUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "PAGEDOWN"]).action, "pageDown")
        XCTAssertTrue(KeyProtocol.isAllowedAction("PageUp"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("pgup"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("pgdn"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("pageDown"))
    }

    // MARK: - wordLeft/wordRight (OPT-13)

    func testCanonicalizeWordLeftAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wordLeft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WordLeft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wleft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WLEFT"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altleft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altLeft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("optleft"), "wordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("optLeft"), "wordLeft")
    }

    func testCanonicalizeWordRightAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wordRight"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WordRight"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wright"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WRIGHT"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altright"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altRight"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("optright"), "wordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("optRight"), "wordRight")
    }

    func testParseKeyWordLeft() {
        let p = KeyProtocol.parseKey(from: ["action": "wordLeft", "count": 2])
        XCTAssertEqual(p.action, "wordLeft")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "wordLeft")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeyWordRight() {
        let p = KeyProtocol.parseKey(from: ["action": "wordRight", "count": 1])
        XCTAssertEqual(p.action, "wordRight")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "wordRight")
    }

    func testParseKeyAliasWleftWright() {
        let l = KeyProtocol.parseKey(from: ["action": "wleft", "count": 1])
        XCTAssertEqual(l.action, "wordLeft")
        XCTAssertEqual(l.allowed, true)
        let r = KeyProtocol.parseKey(from: ["action": "wright"])
        XCTAssertEqual(r.action, "wordRight")
        XCTAssertEqual(r.allowed, true)
    }

    func testParseKeyAliasAltOptLeftRight() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "altleft"]).action, "wordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "optleft"]).action, "wordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "altright"]).action, "wordRight")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "optright"]).action, "wordRight")
        XCTAssertTrue(KeyProtocol.isAllowedAction("wordLeft"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("wordRight"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("WLEFT"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("OptRight"))
    }

    // MARK: - selectLeft/selectRight (OPT-15)

    func testCanonicalizeSelectLeftAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectLeft"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectLeft"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sleft"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SLEFT"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftleft"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftLeft"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sell"), "selectLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELL"), "selectLeft")
    }

    func testCanonicalizeSelectRightAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectRight"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectRight"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sright"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SRIGHT"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftright"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftRight"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("ser"), "selectRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SER"), "selectRight")
    }

    func testParseKeySelectLeft() {
        let p = KeyProtocol.parseKey(from: ["action": "selectLeft", "count": 2])
        XCTAssertEqual(p.action, "selectLeft")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "selectLeft")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeySelectRight() {
        let p = KeyProtocol.parseKey(from: ["action": "selectRight", "count": 1])
        XCTAssertEqual(p.action, "selectRight")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "selectRight")
    }

    func testParseKeySelectLeftCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "selectLeft", "count": 250])
        XCTAssertEqual(hi.action, "selectLeft")
        XCTAssertEqual(hi.count, 200)
        XCTAssertTrue(hi.allowed)
        let lo = KeyProtocol.parseKey(from: ["action": "sright", "count": 0])
        XCTAssertEqual(lo.action, "selectRight")
        XCTAssertEqual(lo.count, 1)
    }

    func testParseKeyAliasSleftSright() {
        let l = KeyProtocol.parseKey(from: ["action": "sleft", "count": 1])
        XCTAssertEqual(l.action, "selectLeft")
        XCTAssertEqual(l.allowed, true)
        let r = KeyProtocol.parseKey(from: ["action": "sright"])
        XCTAssertEqual(r.action, "selectRight")
        XCTAssertEqual(r.allowed, true)
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftleft"]).action, "selectLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftright"]).action, "selectRight")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "sell"]).action, "selectLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "ser"]).action, "selectRight")
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectLeft"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectRight"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SLEFT"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ShiftRight"))
    }

    // MARK: - selectWordLeft/selectWordRight (OPT-16)

    func testCanonicalizeSelectWordLeftAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectWordLeft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectWordLeft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("swleft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SWLEFT"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selwleft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftwordleft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftWordLeft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftoptleft"), "selectWordLeft")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftOptLeft"), "selectWordLeft")
    }

    func testCanonicalizeSelectWordRightAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectWordRight"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectWordRight"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("swright"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SWRIGHT"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selwright"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftwordright"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftWordRight"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftoptright"), "selectWordRight")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftOptRight"), "selectWordRight")
    }

    func testParseKeySelectWordLeft() {
        let p = KeyProtocol.parseKey(from: ["action": "selectWordLeft", "count": 3])
        XCTAssertEqual(p.action, "selectWordLeft")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.reason, "selectWordLeft")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeySelectWordRight() {
        let p = KeyProtocol.parseKey(from: ["action": "selectWordRight", "count": 1])
        XCTAssertEqual(p.action, "selectWordRight")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "selectWordRight")
    }

    func testParseKeySelectWordCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "selectWordLeft", "count": 999])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "selectWordLeft")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "swright", "count": 50])
        XCTAssertEqual(mid.count, 50)
        XCTAssertEqual(mid.action, "selectWordRight")
    }

    func testParseKeyAliasSelectWord() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "swleft"]).action, "selectWordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "swright"]).action, "selectWordRight")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selwleft"]).action, "selectWordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selwright"]).action, "selectWordRight")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftwordleft"]).action, "selectWordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftwordright"]).action, "selectWordRight")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftoptleft"]).action, "selectWordLeft")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftoptright"]).action, "selectWordRight")
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectWordLeft"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectWordRight"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SWLEFT"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ShiftOptRight"))
    }

    // MARK: - selectUp/selectDown (OPT-17)

    func testCanonicalizeSelectUpAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectUp"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectUp"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sup"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SUP"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftup"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftUp"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selu"), "selectUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELU"), "selectUp")
    }

    func testCanonicalizeSelectDownAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectDown"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectDown"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sdn"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SDN"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftdown"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftDown"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("seld"), "selectDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELD"), "selectDown")
    }

    func testParseKeySelectUp() {
        let p = KeyProtocol.parseKey(from: ["action": "selectUp", "count": 2])
        XCTAssertEqual(p.action, "selectUp")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "selectUp")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeySelectDown() {
        let p = KeyProtocol.parseKey(from: ["action": "selectDown", "count": 1])
        XCTAssertEqual(p.action, "selectDown")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "selectDown")
    }

    func testParseKeySelectUpDownCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "selectUp", "count": 250])
        XCTAssertEqual(hi.action, "selectUp")
        XCTAssertEqual(hi.count, 200)
        XCTAssertTrue(hi.allowed)
        let lo = KeyProtocol.parseKey(from: ["action": "sdn", "count": 0])
        XCTAssertEqual(lo.action, "selectDown")
        XCTAssertEqual(lo.count, 1)
    }

    func testParseKeyAliasSelectUpDown() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "sup"]).action, "selectUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "sdn"]).action, "selectDown")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftup"]).action, "selectUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftdown"]).action, "selectDown")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selu"]).action, "selectUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "seld"]).action, "selectDown")
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectUp"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectDown"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SUP"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ShiftDown"))
    }

    // MARK: - selectHome/selectEnd (OPT-18)

    func testCanonicalizeSelectHomeAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectHome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectHome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SHOME"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shifthome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftHome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selhome"), "selectHome")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELHOME"), "selectHome")
    }

    func testCanonicalizeSelectEndAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectEnd"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectEnd"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("send"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SEND"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftend"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftEnd"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selend"), "selectEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELEND"), "selectEnd")
    }

    func testParseKeySelectHome() {
        let p = KeyProtocol.parseKey(from: ["action": "selectHome", "count": 1])
        XCTAssertEqual(p.action, "selectHome")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "selectHome")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeySelectEnd() {
        let p = KeyProtocol.parseKey(from: ["action": "selectEnd", "count": 2])
        XCTAssertEqual(p.action, "selectEnd")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "selectEnd")
    }

    func testParseKeySelectHomeEndCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "selectHome", "count": 999])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "selectHome")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "selend", "count": 50])
        XCTAssertEqual(mid.count, 50)
        XCTAssertEqual(mid.action, "selectEnd")
    }

    func testParseKeyAliasSelectHomeEnd() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shome"]).action, "selectHome")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "send"]).action, "selectEnd")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shifthome"]).action, "selectHome")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftend"]).action, "selectEnd")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selhome"]).action, "selectHome")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selend"]).action, "selectEnd")
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectHome"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectEnd"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SHOME"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ShiftEnd"))
    }

    // MARK: - selectPageUp/selectPageDown (OPT-19)

    func testCanonicalizeSelectPageUpAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectPageUp"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectPageUp"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("spup"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SPUP"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftpgup"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftPgUp"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selpgup"), "selectPageUp")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELPGUP"), "selectPageUp")
    }

    func testCanonicalizeSelectPageDownAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectPageDown"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SelectPageDown"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("spdn"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SPDN"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftpgdn"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftPgDn"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selpgdn"), "selectPageDown")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SELPGDN"), "selectPageDown")
    }

    func testParseKeySelectPageUp() {
        let p = KeyProtocol.parseKey(from: ["action": "selectPageUp", "count": 2])
        XCTAssertEqual(p.action, "selectPageUp")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "selectPageUp")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeySelectPageDown() {
        let p = KeyProtocol.parseKey(from: ["action": "selectPageDown", "count": 1])
        XCTAssertEqual(p.action, "selectPageDown")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "selectPageDown")
    }

    func testParseKeySelectPageUpDownCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "selectPageUp", "count": 999])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "selectPageUp")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "selpgdn", "count": 40])
        XCTAssertEqual(mid.count, 40)
        XCTAssertEqual(mid.action, "selectPageDown")
        let lo = KeyProtocol.parseKey(from: ["action": "spup", "count": 0])
        XCTAssertEqual(lo.count, 1)
        XCTAssertEqual(lo.action, "selectPageUp")
    }

    func testParseKeyAliasSelectPageUpDown() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "spup"]).action, "selectPageUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "spdn"]).action, "selectPageDown")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftpgup"]).action, "selectPageUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftpgdn"]).action, "selectPageDown")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selpgup"]).action, "selectPageUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "selpgdn"]).action, "selectPageDown")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "SelectPageUp"]).action, "selectPageUp")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "SELECTPAGEDOWN"]).action, "selectPageDown")
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectPageUp"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectPageDown"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SPUP"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("ShiftPgDn"))
    }

    // MARK: - redo (+ aliases) (OPT-20)

    func testCanonicalizeRedoAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("redo"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("REDO"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("Redo"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("rdo"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("RDO"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftundo"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("shiftUndo"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdshiftz"), "redo")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("CmdShiftZ"), "redo")
    }

    func testParseKeyRedo() {
        let p = KeyProtocol.parseKey(from: ["action": "redo", "count": 1])
        XCTAssertEqual(p.action, "redo")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "redo")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeyRedoCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "redo", "count": 250])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "redo")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "rdo", "count": 3])
        XCTAssertEqual(mid.count, 3)
        XCTAssertEqual(mid.action, "redo")
    }

    func testParseKeyAliasRedo() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "rdo"]).action, "redo")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "shiftundo"]).action, "redo")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "cmdshiftz"]).action, "redo")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "REDO"]).action, "redo")
        XCTAssertTrue(KeyProtocol.isAllowedAction("redo"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("RDO"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("CmdShiftZ"))
        // undo path still intact
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "undo"]).action, "undo")
        XCTAssertTrue(KeyProtocol.isAllowedAction("undo"))
    }

    // MARK: - lineStart/lineEnd (OPT-21)

    func testCanonicalizeLineStartAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lineStart"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LineStart"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lstart"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LSTART"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdleft"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdLeft"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("bol"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("BOL"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("sol"), "lineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("SOL"), "lineStart")
    }

    func testCanonicalizeLineEndAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lineEnd"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LineEnd"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lend"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LEND"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdright"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdRight"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("softend"), "lineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("softEnd"), "lineEnd")
        // eol still maps to end (document end), not lineEnd
        XCTAssertEqual(KeyProtocol.canonicalizeAction("eol"), "end")
    }

    func testParseKeyLineStart() {
        let p = KeyProtocol.parseKey(from: ["action": "lineStart", "count": 2])
        XCTAssertEqual(p.action, "lineStart")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "lineStart")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeyLineEnd() {
        let p = KeyProtocol.parseKey(from: ["action": "lineEnd", "count": 1])
        XCTAssertEqual(p.action, "lineEnd")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "lineEnd")
    }

    func testParseKeyLineStartEndCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "lineStart", "count": 999])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "lineStart")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "lend", "count": 15])
        XCTAssertEqual(mid.count, 15)
        XCTAssertEqual(mid.action, "lineEnd")
        let lo = KeyProtocol.parseKey(from: ["action": "bol", "count": 0])
        XCTAssertEqual(lo.count, 1)
        XCTAssertEqual(lo.action, "lineStart")
    }

    func testParseKeyAliasLineStartEnd() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "lstart"]).action, "lineStart")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "lend"]).action, "lineEnd")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "cmdleft"]).action, "lineStart")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "cmdright"]).action, "lineEnd")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "bol"]).action, "lineStart")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "sol"]).action, "lineStart")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "softend"]).action, "lineEnd")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "LineStart"]).action, "lineStart")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "LINEEND"]).action, "lineEnd")
        XCTAssertTrue(KeyProtocol.isAllowedAction("lineStart"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("lineEnd"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("LSTART"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("CmdRight"))
        // eol → end, not lineEnd
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "eol"]).action, "end")
        // plain left/right still intact
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "left"]).action, "left")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "right"]).action, "right")
    }

    // MARK: - lineBackspace/lineForwardDelete (OPT-22)

    func testCanonicalizeLineBackspaceAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lineBackspace"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LineBackspace"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lbs"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LBS"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdbs"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdBs"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("deletelinestart"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("deleteLineStart"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("dellinestart"), "lineBackspace")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("delLineStart"), "lineBackspace")
    }

    func testCanonicalizeLineForwardDeleteAliases() {
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lineForwardDelete"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LineForwardDelete"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("lfd"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("LFD"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdfwd"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdFwd"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("deletelineend"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("deleteLineEnd"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("dellineend"), "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("delLineEnd"), "lineForwardDelete")
    }

    func testParseKeyLineBackspace() {
        let p = KeyProtocol.parseKey(from: ["action": "lineBackspace", "count": 2])
        XCTAssertEqual(p.action, "lineBackspace")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.reason, "lineBackspace")
        XCTAssertFalse(p.shouldReject)
    }

    func testParseKeyLineForwardDelete() {
        let p = KeyProtocol.parseKey(from: ["action": "lineForwardDelete", "count": 1])
        XCTAssertEqual(p.action, "lineForwardDelete")
        XCTAssertEqual(p.allowed, true)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "lineForwardDelete")
    }

    func testParseKeyLineDeleteCountClamp() {
        let hi = KeyProtocol.parseKey(from: ["action": "lineBackspace", "count": 300])
        XCTAssertEqual(hi.count, 200)
        XCTAssertEqual(hi.action, "lineBackspace")
        XCTAssertTrue(hi.allowed)
        let mid = KeyProtocol.parseKey(from: ["action": "lfd", "count": 8])
        XCTAssertEqual(mid.count, 8)
        XCTAssertEqual(mid.action, "lineForwardDelete")
        let lo = KeyProtocol.parseKey(from: ["action": "lbs", "count": 0])
        XCTAssertEqual(lo.count, 1)
        XCTAssertEqual(lo.action, "lineBackspace")
    }

    func testParseKeyAliasLineDelete() {
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "lbs"]).action, "lineBackspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "lfd"]).action, "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "cmdbs"]).action, "lineBackspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "cmdfwd"]).action, "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "deletelinestart"]).action, "lineBackspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "dellineend"]).action, "lineForwardDelete")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "LineBackspace"]).action, "lineBackspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "LINEFORWARDDELETE"]).action, "lineForwardDelete")
        XCTAssertTrue(KeyProtocol.isAllowedAction("lineBackspace"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("lineForwardDelete"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("LBS"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("CmdFwd"))
        // plain backspace / forwardDelete still intact
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "backspace"]).action, "backspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "forwardDelete"]).action, "forwardDelete")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "bs"]).action, "backspace")
        XCTAssertEqual(KeyProtocol.parseKey(from: ["action": "fwd"]).action, "forwardDelete")
    }

    // MARK: - bad_count + parseCount (OPT-14)

    func testParseCountDefaultMissing() {
        let p = KeyProtocol.parseCount(from: [:])
        XCTAssertTrue(p.ok)
        XCTAssertEqual(p.value, 1)
        XCTAssertEqual(p.reason, "")
    }

    func testParseCountNullDefaults() {
        let p = KeyProtocol.parseCount(from: ["count": NSNull()])
        XCTAssertTrue(p.ok)
        XCTAssertEqual(p.value, 1)
    }

    func testParseCountValidIntDoubleString() {
        XCTAssertEqual(KeyProtocol.parseCount(from: ["count": 7]).value, 7)
        XCTAssertTrue(KeyProtocol.parseCount(from: ["count": 7]).ok)
        XCTAssertEqual(KeyProtocol.parseCount(from: ["count": 3.9]).value, 3)
        XCTAssertEqual(KeyProtocol.parseCount(from: ["count": "12"]).value, 12)
        XCTAssertTrue(KeyProtocol.parseCount(from: ["count": "12"]).ok)
        XCTAssertEqual(KeyProtocol.parseCount(from: ["count": 250]).value, 200)
        XCTAssertEqual(KeyProtocol.parseCount(from: ["count": 0]).value, 1)
        // count 1 must not be confused with Bool true via NSNumber bridging
        let one = KeyProtocol.parseCount(from: ["count": 1])
        XCTAssertTrue(one.ok, "count:1 must parse ok (not bad_count via Bool bridge)")
        XCTAssertEqual(one.value, 1)
        let nOne = KeyProtocol.parseCount(from: ["count": NSNumber(value: 1)])
        XCTAssertTrue(nOne.ok)
        XCTAssertEqual(nOne.value, 1)
        let nZero = KeyProtocol.parseCount(from: ["count": NSNumber(value: 0)])
        XCTAssertTrue(nZero.ok)
        XCTAssertEqual(nZero.value, 1) // clamp
    }

    func testParseCountJSONBoolVsIntOne() {
        // JSON true → CFBoolean → bad_count; JSON 1 → NSNumber int → ok
        let jsonTrue = try! JSONSerialization.jsonObject(with: Data(#"{"count":true}"#.utf8)) as! [String: Any]
        let bad = KeyProtocol.parseCount(from: jsonTrue)
        XCTAssertFalse(bad.ok)
        XCTAssertEqual(bad.reason, "bad_count")
        let jsonOne = try! JSONSerialization.jsonObject(with: Data(#"{"count":1}"#.utf8)) as! [String: Any]
        let ok = KeyProtocol.parseCount(from: jsonOne)
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(ok.value, 1)
    }

    func testParseCountBadBool() {
        let p = KeyProtocol.parseCount(from: ["count": true])
        XCTAssertFalse(p.ok)
        XCTAssertEqual(p.reason, "bad_count")
        XCTAssertEqual(p.value, 1)
    }

    func testParseCountBadArrayDict() {
        let a = KeyProtocol.parseCount(from: ["count": [1, 2]])
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.reason, "bad_count")
        let d = KeyProtocol.parseCount(from: ["count": ["n": 1]])
        XCTAssertFalse(d.ok)
        XCTAssertEqual(d.reason, "bad_count")
    }

    func testParseCountBadNonIntString() {
        let p = KeyProtocol.parseCount(from: ["count": "abc"])
        XCTAssertFalse(p.ok)
        XCTAssertEqual(p.reason, "bad_count")
        let empty = KeyProtocol.parseCount(from: ["count": "  "])
        XCTAssertFalse(empty.ok)
        XCTAssertEqual(empty.reason, "bad_count")
    }

    func testParseCountBadRepeat() {
        let p = KeyProtocol.parseCount(from: ["repeat": false])
        XCTAssertFalse(p.ok)
        XCTAssertEqual(p.reason, "bad_count")
    }

    func testParseKeyBadCountBool() {
        let p = KeyProtocol.parseKey(from: ["action": "backspace", "count": true])
        XCTAssertEqual(p.reason, "bad_count")
        XCTAssertTrue(p.isBadCount)
        XCTAssertTrue(p.shouldReject)
        XCTAssertFalse(p.allowed)
        XCTAssertEqual(p.action, "backspace") // action still parsed
    }

    func testParseKeyBadCountArray() {
        let p = KeyProtocol.parseKey(from: ["action": "left", "count": [3]])
        XCTAssertEqual(p.reason, "bad_count")
        XCTAssertTrue(p.shouldReject)
    }

    func testParseKeyBadCountNonIntString() {
        let p = KeyProtocol.parseKey(from: ["action": "wordLeft", "count": "nope"])
        XCTAssertEqual(p.reason, "bad_count")
        XCTAssertTrue(p.shouldReject)
    }

    func testParseKeyValidCountStillClamps() {
        let p = KeyProtocol.parseKey(from: ["action": "backspace", "count": 999])
        XCTAssertEqual(p.reason, "backspace")
        XCTAssertEqual(p.count, 200)
        XCTAssertFalse(p.shouldReject)
        let s = KeyProtocol.parseKey(from: ["action": "right", "count": "5"])
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.reason, "right")
        XCTAssertFalse(s.shouldReject)
    }

    func testParseKeyMissingCountDefaultsOne() {
        let p = KeyProtocol.parseKey(from: ["action": "wordRight"])
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.reason, "wordRight")
        XCTAssertFalse(p.shouldReject)
    }

    // MARK: - OPT-23 selectLineStart / selectLineEnd

    func testSelectLineStartEndAllowed() {
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectLineStart"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("selectLineEnd"))
        XCTAssertTrue(KeyProtocol.isAllowedAction("SelectLineStart"))
        XCTAssertEqual(KeyProtocol.canonicalizeAction("slstart"), "selectLineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdshiftleft"), "selectLineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("slend"), "selectLineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("cmdshiftright"), "selectLineEnd")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectlinestart"), "selectLineStart")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("selectlineend"), "selectLineEnd")
    }

    func testParseKeySelectLineStartEnd() {
        let a = KeyProtocol.parseKey(from: ["action": "selectLineStart", "count": 2])
        XCTAssertEqual(a.action, "selectLineStart")
        XCTAssertEqual(a.count, 2)
        XCTAssertTrue(a.allowed)
        XCTAssertFalse(a.shouldReject)
        let b = KeyProtocol.parseKey(from: ["action": "slend", "count": 1])
        XCTAssertEqual(b.action, "selectLineEnd")
        XCTAssertEqual(b.reason, "selectLineEnd")
        XCTAssertTrue(b.allowed)
    }


    // MARK: - H1-6 wordForwardDelete

    func testWordForwardDeleteAllowedAndAliases() {
        XCTAssertTrue(KeyProtocol.isAllowedAction("wordForwardDelete"))
        XCTAssertEqual(KeyProtocol.canonicalizeAction("wfd"), "wordForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("altfwd"), "wordForwardDelete")
        XCTAssertEqual(KeyProtocol.canonicalizeAction("WordForwardDelete"), "wordForwardDelete")
        let p = KeyProtocol.parseKey(from: ["action": "wfd", "count": 2])
        XCTAssertEqual(p.action, "wordForwardDelete")
        XCTAssertEqual(p.count, 2)
        XCTAssertTrue(p.allowed)
        XCTAssertFalse(p.shouldReject)
    }

}
