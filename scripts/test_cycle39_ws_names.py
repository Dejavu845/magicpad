#!/usr/bin/env python3
"""Cycle 39: WS types are names, not HTTP paths."""

from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    CLASSIFY_HTTP_PATH,
    HTTP_ROUTES,
    WS_TYPES,
    is_documented_http_path,
    ws_types_are_names_not_paths,
)


class Cycle39WSNamesTests(unittest.TestCase):
    def test_ws_types_have_no_slash(self) -> None:
        self.assertTrue(ws_types_are_names_not_paths())
        self.assertIn("classify", WS_TYPES)
        self.assertNotIn("/classify", WS_TYPES)
        self.assertIsNone(CLASSIFY_HTTP_PATH)

    def test_classify_hello_ping_are_not_routes(self) -> None:
        # `stt` is the one WS type that also has POST /stt.
        for name in ("classify", "hello", "ping", "voice", "key", "type", "text"):
            self.assertFalse(is_documented_http_path(f"/{name}"))
        self.assertTrue(is_documented_http_path("/stt"))


if __name__ == "__main__":
    unittest.main()
