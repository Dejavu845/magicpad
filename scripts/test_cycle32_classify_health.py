#!/usr/bin/env python3
"""Cycle 32: classify is WS telemetry — never a GET /health key."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    CLASSIFY_INJECTS,
    CLASSIFY_IS_HEALTH_KEY,
    FORBIDDEN_HEALTH_KEYS,
    health_allows_key,
)


def _health_keys_blob() -> str:
    proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(encoding="utf-8")
    start = proto.find("### `GET /health` keys")
    nxt = proto.find("\n### ", start + 5)
    if nxt < 0:
        nxt = proto.find("\n## ", start + 5)
    return proto[start:nxt]


class Cycle32ClassifyHealthTests(unittest.TestCase):
    def test_classify_is_not_a_health_key(self) -> None:
        self.assertFalse(CLASSIFY_INJECTS)
        self.assertFalse(CLASSIFY_IS_HEALTH_KEY)
        self.assertFalse(health_allows_key("classify"))
        self.assertIn("classify", FORBIDDEN_HEALTH_KEYS)
        self.assertTrue(health_allows_key("proto"))
        self.assertTrue(health_allows_key("ok"))

    def test_protocol_health_keys_line_omits_classify(self) -> None:
        blob = _health_keys_blob()
        keys = next(ln for ln in blob.splitlines() if ln.startswith("`ok`"))
        self.assertNotIn("classify", keys)
        self.assertIn("`proto`", keys)

    def test_swift_classify_flag(self) -> None:
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "Classify.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("public static let isHealthKey = false", text)
        self.assertIn("public static let injects = false", text)

    def test_pairing_token_forbids_classify(self) -> None:
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "PairingToken.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("Classify.jsonType", text)

    def test_local_health_json_omits_classify(self) -> None:
        ws = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "WebSocketServer.swift",
        ).read_text(encoding="utf-8")
        if len(ws.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        start = ws.find("func healthJSON")
        end = ws.find("func fallbackHTML", start)
        chunk = ws[start:end]
        self.assertNotIn('"classify"', chunk)
        self.assertIn('"proto"', chunk)


if __name__ == "__main__":
    unittest.main()
