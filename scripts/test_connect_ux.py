#!/usr/bin/env python3
"""First-connect honesty: Whisper empty state, pairing PIN (not in QR), route chip."""
from __future__ import annotations

import os
import re
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import pairing_allows, pairing_merge_configured, qr_url_is_safe  # noqa: E402

ROOT = os.path.dirname(HERE)
HTML = os.path.join(ROOT, "MagicPadClient", "index.html")
PAIR_SWIFT = os.path.join(
    ROOT, "MagicPadServer", "Sources", "MagicPadCore", "PairingToken.swift"
)
MENU_SWIFT = os.path.join(
    ROOT, "MagicPadServer", "Sources", "MagicPadServer", "MagicPadServer.swift"
)
WS_SWIFT = os.path.join(
    ROOT, "MagicPadServer", "Sources", "MagicPadServer", "WebSocketServer.swift"
)


class ConnectUxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = Path(HTML).read_text(encoding="utf-8")
        cls.pair = Path(PAIR_SWIFT).read_text(encoding="utf-8")
        cls.menu = Path(MENU_SWIFT).read_text(encoding="utf-8")
        cls.ws = Path(WS_SWIFT).read_text(encoding="utf-8")

    def test_html_rev_bumped(self):
        m = re.search(r"MAGICPAD_HTML_REV\s*=\s*'(\d{8}-\d{4}-h(\d+))'", self.html)
        self.assertIsNotNone(m)
        self.assertGreaterEqual(int(m.group(2)), 811)

    def test_whisper_missing_copy(self):
        self.assertIn('id="whisperMissingNote"', self.html)
        self.assertIn("whisperWeightsMissing", self.html)
        self.assertIn("未下载 Whisper", self.html)
        self.assertIn("触控可用", self.html)
        self.assertIn("fetch-whisper-model.sh", self.html)

    def test_pair_row_not_in_qr(self):
        self.assertIn('id="connectPairRow"', self.html)
        self.assertIn('id="pairInput"', self.html)
        self.assertIn("magicpad_pair", self.html)
        self.assertIn("X-MagicPad-Pair", self.html)
        self.assertNotIn("pair=", self.html.lower())
        self.assertTrue(qr_url_is_safe("http://10.8.0.2:7878/?auto=1", configured="123456"))  # example-ip

    def test_webm_honesty(self):
        self.assertIn("webm", self.html)
        self.assertIn("系统键盘听写", self.html)

    def test_route_chip(self):
        self.assertIn("routeIface", self.html)
        self.assertIn(" · 路由", self.html)

    def test_pairing_merge_env_wins(self):
        self.assertEqual(pairing_merge_configured("envpin", "menupin"), "envpin")
        self.assertEqual(pairing_merge_configured("", "menupin"), "menupin")
        self.assertIsNone(pairing_merge_configured("", ""))
        self.assertTrue(pairing_allows(None, configured=None))
        self.assertFalse(pairing_allows(None, configured="123456"))
        self.assertTrue(pairing_allows("123456", configured="123456"))

    def test_swift_has_merge_and_pin(self):
        self.assertIn("func mergeConfigured", self.pair)
        self.assertIn("func generatePin", self.pair)
        self.assertIn("PairingRuntime", self.menu)
        self.assertIn("未下载 · 触控可用", self.menu)
        self.assertIn("helloPaired", self.ws)
        self.assertIn("x-magicpad-pair", self.ws.lower())
        self.assertIn("pairing_required", self.ws)


if __name__ == "__main__":
    unittest.main()
