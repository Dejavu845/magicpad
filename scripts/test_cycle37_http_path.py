#!/usr/bin/env python3
"""Cycle 37: only documented HTTP paths. classify is not a route."""

from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    CERT_PATH,
    CLASSIFY_HTTP_PATH,
    HTTP_ROUTES,
    is_documented_http_path,
)


class Cycle37HTTPPathTests(unittest.TestCase):
    def test_documented_paths(self) -> None:
        self.assertTrue(is_documented_http_path("/"))
        self.assertTrue(is_documented_http_path("/health"))
        self.assertTrue(is_documented_http_path("/stt"))
        self.assertTrue(is_documented_http_path("/drop"))
        self.assertTrue(is_documented_http_path("/cert"))
        self.assertTrue(is_documented_http_path("/cert/"))
        self.assertEqual(CERT_PATH, "/cert")
        self.assertIn(CERT_PATH, HTTP_ROUTES)

    def test_classify_and_pair_are_not_routes(self) -> None:
        self.assertFalse(is_documented_http_path("/classify"))
        self.assertFalse(is_documented_http_path("/pair"))
        self.assertIsNone(CLASSIFY_HTTP_PATH)


if __name__ == "__main__":
    unittest.main()
