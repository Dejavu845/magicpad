#!/usr/bin/env python3
"""Cycle 30: classify is telemetry only — never inject."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import CLASSIFY_INJECTS, parse_classify_kind  # noqa: E402


class Cycle30ClassifyTests(unittest.TestCase):
    def test_python_never_injects(self):
        self.assertFalse(CLASSIFY_INJECTS)
        self.assertEqual(parse_classify_kind(" pinch "), "pinch")
        self.assertIsNone(parse_classify_kind(None))
        self.assertIsNone(parse_classify_kind("   "))

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "Classify.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(path.stat().st_size, 200)
        self.assertIn("injects = false", text)
        self.assertIn('jsonType = "classify"', text)
        live = "\n".join(
            ln.split("//")[0] for ln in text.splitlines() if not ln.lstrip().startswith("//")
        )
        self.assertNotIn("CGEvent", live)
        self.assertNotIn("injectMouse", live)

    def test_local_server_does_not_inject(self):
        ws = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "WebSocketServer.swift",
        ).read_text(encoding="utf-8")
        if len(ws.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        start = ws.find("func handleClassify")
        end = ws.find("\n    private func ", start + 10)
        chunk = ws[start:end]
        self.assertIn("Classify.parseKind", chunk)
        self.assertIn("Classify.injects", chunk)
        self.assertNotIn("EventInjector", chunk)
        self.assertNotIn("injectEditAction", chunk)


if __name__ == "__main__":
    unittest.main()
