#!/usr/bin/env python3
"""Cycle 38: HTTP route list is closed. No silent extra route."""

from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    CLASSIFY_HTTP_PATH,
    HTTP_ROUTE_COUNT,
    HTTP_ROUTES,
    is_documented_http_path,
)


class Cycle38HTTPCountTests(unittest.TestCase):
    def test_closed_list(self) -> None:
        self.assertEqual(len(HTTP_ROUTES), HTTP_ROUTE_COUNT)
        self.assertEqual(HTTP_ROUTE_COUNT, 5)
        self.assertEqual(len(set(HTTP_ROUTES)), HTTP_ROUTE_COUNT)
        self.assertIsNone(CLASSIFY_HTTP_PATH)
        self.assertFalse(is_documented_http_path("/classify"))
        self.assertFalse(is_documented_http_path("/hello"))


if __name__ == "__main__":
    unittest.main()
