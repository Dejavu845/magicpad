#!/usr/bin/env python3
"""Cycle 24: STT lang allowlist lives in Core + Python."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import STT_LANGS, STT_LANG_FALLBACK, parse_stt_lang  # noqa: E402


class Cycle24STTLangTests(unittest.TestCase):
    def test_python_allowlist(self):
        self.assertEqual(parse_stt_lang("zh-CN"), "zh-CN")
        self.assertEqual(parse_stt_lang("en-US"), "en-US")
        self.assertEqual(parse_stt_lang("ja-JP"), "ja-JP")
        self.assertEqual(parse_stt_lang(None), "zh-CN")
        self.assertEqual(parse_stt_lang(""), "zh-CN")
        self.assertEqual(parse_stt_lang("en-us"), "zh-CN")
        self.assertEqual(parse_stt_lang("fr-FR"), "zh-CN")
        self.assertEqual(STT_LANGS, frozenset({"zh-CN", "en-US", "ja-JP"}))
        self.assertEqual(STT_LANG_FALLBACK, "zh-CN")

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "STTLang.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(path.stat().st_size, 200)
        self.assertIn('"zh-CN"', text)
        self.assertIn('"en-US"', text)
        self.assertIn('"ja-JP"', text)
        self.assertIn('fallback = "zh-CN"', text)
        self.assertIn("public static func parse", text)

    def test_local_server_uses_core_parser(self):
        ws = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "WebSocketServer.swift",
        ).read_text(encoding="utf-8")
        if len(ws.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        self.assertIn("STTLang.parse", ws)


if __name__ == "__main__":
    unittest.main()
