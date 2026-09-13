// VoiceProtocolTests.swift — parseVoice clamp / defaults (no AppKit, no LLM)

import XCTest
@testable import MagicPadCore

final class VoiceProtocolTests: XCTestCase {
    func testEmptyAndWhitespace() {
        XCTAssertEqual(KeyProtocol.parseVoice(from: [:]).reason, "empty")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": NSNull()]).reason, "empty")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": ""]).reason, "empty")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": "   \n"]).reason, "empty")
        XCTAssertTrue(KeyProtocol.parseVoice(from: ["text": ""]).isEmpty)
    }

    func testNonStringText() {
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": 123]).reason, "bad_voice")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": true]).reason, "bad_voice")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": ["a"]]).reason, "bad_voice")
        XCTAssertFalse(KeyProtocol.parseVoice(from: ["text": 123]).isEmpty)
    }

    func testExactMaxNotTruncated() {
        let s = String(repeating: "a", count: KeyProtocol.maxVoiceChars)
        let p = KeyProtocol.parseVoice(from: ["text": s])
        XCTAssertFalse(p.truncated)
        XCTAssertNil(p.reason)
        XCTAssertEqual(p.text.count, KeyProtocol.maxVoiceChars)
    }

    func testOversizeTrailingEmojiTruncatesAtGrapheme() {
        let s = String(repeating: "a", count: KeyProtocol.maxVoiceChars) + "🙂"
        let p = KeyProtocol.parseVoice(from: ["text": s])
        XCTAssertTrue(p.truncated)
        XCTAssertEqual(p.reason, "voice_truncated")
        XCTAssertEqual(p.text.count, KeyProtocol.maxVoiceChars)
        XCTAssertFalse(p.text.contains("🙂"))
        XCTAssertEqual(p.text, String(repeating: "a", count: KeyProtocol.maxVoiceChars))
    }

    func testBadLangDefaultsZh() {
        let p = KeyProtocol.parseVoice(from: ["text": "hi", "lang": "fr-FR"])
        XCTAssertEqual(p.lang, "zh-CN")
        XCTAssertNil(p.reason)
    }

    func testGoodLangs() {
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": "a", "lang": "en-US"]).lang, "en-US")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": "a", "lang": "ja-JP"]).lang, "ja-JP")
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": "a", "lang": "zh-CN"]).lang, "zh-CN")
    }

    func testBadModeDefaultsAppend() {
        let p = KeyProtocol.parseVoice(from: ["text": "hi", "mode": "merge"])
        XCTAssertEqual(p.mode, "append")
    }

    func testReplaceMode() {
        XCTAssertEqual(KeyProtocol.parseVoice(from: ["text": "hi", "mode": "replace"]).mode, "replace")
    }

    func testAutoPasteNonBooleanDefaultsTrue() {
        let p = KeyProtocol.parseVoice(from: ["text": "hi", "autoPaste": "yes"])
        XCTAssertTrue(p.autoPaste)
    }

    func testAutoPasteFalse() {
        let json = try! JSONSerialization.jsonObject(with: Data(#"{"text":"hi","autoPaste":false}"#.utf8)) as! [String: Any]
        let p = KeyProtocol.parseVoice(from: json)
        XCTAssertFalse(p.autoPaste)
    }

    func testMaxVoiceCharsConstant() {
        XCTAssertEqual(KeyProtocol.maxVoiceChars, 20_000)
    }
}
