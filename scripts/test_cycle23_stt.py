#!/usr/bin/env python3
"""Cycle 23: STT action aliases live in Core + Python (MP-18)."""
from __future__ import annotations

import os
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
import sys

sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    parse_stt_action,
    STT_START,
    STT_STATUS,
    STT_STOP,
)


def _swift_core(name: str) -> Path:
    return Path(
        os.path.dirname(HERE),
        "MagicPadServer",
        "Sources",
        "MagicPadCore",
        name,
    )


class Cycle23STTActionTests(unittest.TestCase):
    def test_python_aliases(self):
        self.assertEqual(parse_stt_action("start"), "start")
        self.assertEqual(parse_stt_action("BEGIN"), "start")
        self.assertEqual(parse_stt_action(" on "), "start")
        self.assertEqual(parse_stt_action("stop"), "stop")
        self.assertEqual(parse_stt_action("end"), "stop")
        self.assertEqual(parse_stt_action("OFF"), "stop")
        self.assertEqual(parse_stt_action("status"), "status")
        self.assertIsNone(parse_stt_action(None))
        self.assertIsNone(parse_stt_action(""))
        self.assertIsNone(parse_stt_action("listen"))
        self.assertIsNone(parse_stt_action("pair"))
        self.assertEqual(STT_START, frozenset({"start", "begin", "on"}))
        self.assertEqual(STT_STOP, frozenset({"stop", "end", "off"}))
        self.assertEqual(STT_STATUS, frozenset({"status"}))

    def test_swift_core_table(self):
        text = _swift_core("STTAction.swift").read_text(encoding="utf-8")
        self.assertGreaterEqual(_swift_core("STTAction.swift").stat().st_size, 200)
        self.assertIn("startAliases", text)
        self.assertIn('"begin"', text)
        self.assertIn('"on"', text)
        self.assertIn('"end"', text)
        self.assertIn('"off"', text)
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
        self.assertIn("STTAction.parse", ws)


if __name__ == "__main__":
    unittest.main()
