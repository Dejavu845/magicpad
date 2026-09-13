#!/usr/bin/env python3
"""Cycle 26: binary pointer/gesture parse lives in Core + Python (MP-18)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    PHASES,
    frame13,
    frame18,
    parse_binary_frame,
)


class Cycle26BinaryFrameTests(unittest.TestCase):
    def test_python_too_short_is_none(self):
        self.assertIsNone(parse_binary_frame(b""))
        self.assertIsNone(parse_binary_frame(b"\x00" * 6))
        self.assertIsNotNone(parse_binary_frame(b"\x00" * 7))

    def test_python_frame13_matches_builder(self):
        raw = frame13(0, dx=10, dy=-10, buttons=1)
        parsed = parse_binary_frame(raw)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed["phase"], 0)
        self.assertEqual(parsed["dx"], 10)
        self.assertEqual(parsed["dy"], -10)
        self.assertEqual(parsed["buttons"], 1)
        self.assertEqual(parsed["kind"], "down")
        self.assertFalse(parsed["is_gesture"])

    def test_python_frame18_pinch(self):
        raw = frame18(21, fingers=2, gesture=1, ext=1000)
        parsed = parse_binary_frame(raw)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed["kind"], "pinch")
        self.assertEqual(parsed["fingers"], 2)
        self.assertEqual(parsed["gesture"], 1)
        self.assertEqual(parsed["ext"], 1000)
        self.assertTrue(parsed["is_gesture"])

    def test_unknown_phase_stays_unknown(self):
        parsed = parse_binary_frame(bytes([99]) + b"\x00" * 6)
        self.assertEqual(parsed["kind"], "unknown")
        self.assertNotIn(99, PHASES)

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "BinaryFrame.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(path.stat().st_size, 200)
        self.assertIn("minBytes = 7", text)
        self.assertIn("pointerBytes = 13", text)
        self.assertIn("gestureBytes = 18", text)
        self.assertIn("public static func parse", text)
        self.assertIn('"down"', text)
        self.assertIn('"pinch"', text)
        self.assertIn('"unknown"', text)
        self.assertNotIn("CGEvent", text)
        self.assertNotIn("injectMouse", text)

    def test_local_server_uses_core_parser(self):
        root = Path(os.path.dirname(HERE))
        inj = (root / "MagicPadServer/Sources/MagicPadServer/EventInjector.swift").read_text(
            encoding="utf-8"
        )
        if len(inj.encode("utf-8")) < 20_000:
            self.skipTest("EventInjector.swift is the remote stub")
        self.assertIn("BinaryFrame.parse", inj)
        ws = (root / "MagicPadServer/Sources/MagicPadServer/WebSocketServer.swift").read_text(
            encoding="utf-8"
        )
        if len(ws.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        self.assertIn("BinaryFrame.parse", ws)


if __name__ == "__main__":
    unittest.main()
