#!/usr/bin/env python3
"""Cycle 33: classify is WS telemetry — no HTTP /classify route."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    CLASSIFY_HTTP_PATH,
    CLASSIFY_INJECTS,
    CLASSIFY_IS_HEALTH_KEY,
)


def _http_blob() -> str:
    proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(encoding="utf-8")
    start = proto.find("## HTTP")
    nxt = proto.find("\n## ", start + 5)
    return proto[start:nxt]


class Cycle33ClassifyHTTPTests(unittest.TestCase):
    def test_no_http_path(self) -> None:
        self.assertIsNone(CLASSIFY_HTTP_PATH)
        self.assertFalse(CLASSIFY_INJECTS)
        self.assertFalse(CLASSIFY_IS_HEALTH_KEY)

    def test_protocol_http_table_omits_classify_route(self) -> None:
        blob = _http_blob()
        self.assertIn("`POST /stt`", blob)
        self.assertIn("`POST /drop`", blob)
        self.assertIn("`GET /health`", blob)
        self.assertNotIn("/classify", blob)

    def test_swift_http_path_nil(self) -> None:
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "Classify.swift",
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("public static let httpPath: String? = nil", text)
        self.assertIn("public static let injects = false", text)


if __name__ == "__main__":
    unittest.main()
