#!/usr/bin/env python3
"""Cycle 25: STT onDevice JSON bool lives in Core + Python."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import parse_stt_on_device  # noqa: E402


class Cycle25STTOnDeviceTests(unittest.TestCase):
    def test_python_json_bool(self):
        self.assertTrue(parse_stt_on_device(True))
        self.assertFalse(parse_stt_on_device(False))
        self.assertTrue(parse_stt_on_device(None))
        self.assertTrue(parse_stt_on_device("true"))
        self.assertTrue(parse_stt_on_device(1))
        self.assertTrue(parse_stt_on_device(0))

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "STTOnDevice.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(path.stat().st_size, 200)
        self.assertIn('jsonField = "onDevice"', text)
        self.assertIn("defaultOn = true", text)
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
        self.assertIn("STTOnDevice.parse", ws)


if __name__ == "__main__":
    unittest.main()
