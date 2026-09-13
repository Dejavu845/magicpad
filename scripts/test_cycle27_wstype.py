#!/usr/bin/env python3
"""Cycle 27: inbound WS JSON type allowlist lives in Core + Python."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import WS_TYPES, parse_ws_type  # noqa: E402


class Cycle27WSTypeTests(unittest.TestCase):
    def test_python_allowlist(self):
        for name in (
            "voice",
            "key",
            "type",
            "text",
            "stt",
            "hello",
            "ping",
            "classify",
        ):
            self.assertEqual(parse_ws_type(name), name)
        self.assertEqual(parse_ws_type(" ping "), "ping")
        self.assertIsNone(parse_ws_type(None))
        self.assertIsNone(parse_ws_type(""))
        self.assertIsNone(parse_ws_type("Hello"))
        self.assertIsNone(parse_ws_type("drop"))
        self.assertIsNone(parse_ws_type("upload"))
        self.assertIsNone(parse_ws_type("pair"))
        self.assertNotIn("drop", WS_TYPES)

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "WSType.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(path.stat().st_size, 200)
        self.assertIn("public static func parse", text)
        self.assertIn("case hello", text)
        self.assertIn("case classify", text)
        self.assertNotIn("CGEvent", text)
        self.assertIn("Does not invent drop/upload as WS types", text)
        self.assertNotIn("case drop", text)

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
        self.assertIn("WSType.parse", ws)


if __name__ == "__main__":
    unittest.main()
