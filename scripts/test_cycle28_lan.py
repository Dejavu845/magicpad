#!/usr/bin/env python3
"""Cycle 28: QR LAN check uses the Core/Python RFC1918 gate (MP-18)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from generate_qr import is_private  # noqa: E402
from lan_fixtures import LAN_FIXTURES  # noqa: E402
from magicpad_proto import is_private_ipv4  # noqa: E402


class Cycle28LANTests(unittest.TestCase):
    def test_qr_matches_core_gate(self):
        self.assertTrue(is_private("10.8.0.2"))  # example-ip
        self.assertTrue(is_private("192.168.1.5"))  # example-ip
        self.assertTrue(is_private("172.16.0.1"))  # example-ip
        self.assertFalse(is_private("127.0.0.1"))
        self.assertFalse(is_private("8.8.8.8"))
        self.assertFalse(is_private("10.a.0.0.1"))  # example-ip
        self.assertFalse(is_private("+10.0.0.1"))  # example-ip
        self.assertFalse(is_private("10.0000.0.1"))  # example-ip
        self.assertFalse(is_private("172.15.0.1"))
        for ip, expected, note in LAN_FIXTURES:
            with self.subTest(ip=ip, note=note):
                self.assertEqual(is_private(ip), expected)
                self.assertEqual(is_private(ip), is_private_ipv4(ip))

    def test_generate_qr_delegates(self):
        text = Path(HERE, "generate_qr.py").read_text(encoding="utf-8")
        self.assertIn("return is_private_ipv4(ip)", text)
        self.assertIn("from magicpad_proto import", text)
        self.assertNotIn("int(parts[0])", text)


if __name__ == "__main__":
    unittest.main()
