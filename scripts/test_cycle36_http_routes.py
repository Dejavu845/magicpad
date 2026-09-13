#!/usr/bin/env python3
"""Cycle 36: documented HTTP routes. classify is not one of them."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import CLASSIFY_HTTP_PATH, HTTP_ROUTES  # noqa: E402


def _http_table() -> str:
    proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(encoding="utf-8")
    start = proto.find("## HTTP")
    nxt = proto.find("\n### ", start + 5)
    return proto[start:nxt]


class Cycle36HTTPRoutesTests(unittest.TestCase):
    def test_routes_are_the_five_documented(self) -> None:
        self.assertEqual(HTTP_ROUTES, ("/", "/health", "/stt", "/drop", "/cert"))
        self.assertIsNone(CLASSIFY_HTTP_PATH)
        self.assertNotIn("/classify", HTTP_ROUTES)

    def test_protocol_table_lists_only_those_routes(self) -> None:
        blob = _http_table()
        for route in HTTP_ROUTES:
            if route == "/":
                self.assertIn("`GET /`", blob)
            elif route == "/health":
                self.assertIn("`GET /health`", blob)
            elif route == "/stt":
                self.assertIn("`POST /stt`", blob)
            elif route == "/drop":
                self.assertIn("`POST /drop`", blob)
            elif route == "/cert":
                self.assertIn("`GET /cert`", blob)
        self.assertNotIn("/classify", blob)


if __name__ == "__main__":
    unittest.main()
