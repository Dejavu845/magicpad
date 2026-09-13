#!/usr/bin/env python3
"""Cycle 29: pairing token / hello.pair must never be GET /health keys."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    FORBIDDEN_HEALTH_KEYS,
    PAIRING_ENV,
    PAIRING_HELLO_FIELD,
    health_allows_key,
)


def _health_keys_blob() -> str:
    proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(encoding="utf-8")
    start = proto.find("### `GET /health` keys")
    nxt = proto.find("\n### ", start + 5)
    if nxt < 0:
        nxt = proto.find("\n## ", start + 5)
    return proto[start:nxt]


class Cycle29HealthPairTests(unittest.TestCase):
    def test_python_forbids_pair_keys(self):
        self.assertFalse(health_allows_key("pair"))
        self.assertFalse(health_allows_key(PAIRING_ENV))
        self.assertTrue(health_allows_key("proto"))
        self.assertTrue(health_allows_key("ok"))
        self.assertEqual(FORBIDDEN_HEALTH_KEYS, frozenset({PAIRING_HELLO_FIELD, PAIRING_ENV}))

    def test_protocol_health_table_omits_pair(self):
        blob = _health_keys_blob()
        keys = next(ln for ln in blob.splitlines() if ln.startswith("`ok`"))
        self.assertIn("`proto`", keys)
        self.assertNotIn("`pair`", keys)
        self.assertNotIn(PAIRING_ENV, keys)
        self.assertIn("never", blob.lower())

    def test_swift_core_table(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "PairingToken.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("forbiddenHealthKeys", text)
        self.assertIn("healthAllowsKey", text)
        self.assertIn(PAIRING_ENV, text)

    def test_local_health_json_omits_pair(self):
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
        self.assertIn('"proto"', chunk)
        self.assertNotIn('"pair"', chunk)
        self.assertNotIn(PAIRING_ENV, chunk)


if __name__ == "__main__":
    unittest.main()
