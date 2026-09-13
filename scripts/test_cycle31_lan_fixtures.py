#!/usr/bin/env python3
"""Cycle 31: shared LAN fixtures. generate_qr.is_private == is_private_ipv4 on every row."""

from __future__ import annotations

import ast
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from generate_qr import is_private, is_private_ipv4  # noqa: E402
from lan_fixtures import LAN_FIXTURES  # noqa: E402


class TestCycle31LanFixtures(unittest.TestCase):
    def test_table_matches_json_and_has_rfc1918(self) -> None:
        raw = json.loads(
            (ROOT / "scripts" / "fixtures" / "lan-vectors.json").read_text(encoding="utf-8")
        )
        ips = [ip for ip, _, _ in LAN_FIXTURES]
        self.assertEqual(ips, [str(row["ip"]) for row in raw["vectors"]])
        self.assertIn("10.8.0.2", ips)  # example-ip
        self.assertIn("192.168.1.5", ips)  # example-ip
        self.assertIn("+10.0.0.1", ips)  # example-ip
        self.assertIn("10.a.0.0.1", ips)  # example-ip
        self.assertGreaterEqual(len(LAN_FIXTURES), 16)

    def test_loopback_and_link_local_are_not_lan(self) -> None:
        by_ip = {ip: expected for ip, expected, _ in LAN_FIXTURES}
        self.assertFalse(by_ip["127.0.0.1"])
        self.assertFalse(by_ip["169.254.1.1"])

    def test_every_row_matches_both_parsers(self) -> None:
        for ip, expected, note in LAN_FIXTURES:
            with self.subTest(ip=ip, note=note):
                self.assertEqual(is_private_ipv4(ip), expected)
                self.assertEqual(is_private(ip), expected)
                self.assertEqual(is_private(ip), is_private_ipv4(ip))

    def test_c28_imports_shared_table(self) -> None:
        src = (ROOT / "scripts" / "test_cycle28_lan.py").read_text(encoding="utf-8")
        self.assertIn("from lan_fixtures import LAN_FIXTURES", src)

    def test_swift_samples_cover_table_ips(self) -> None:
        swift = (
            ROOT / "MagicPadServer" / "Tests" / "MagicPadServerTests" / "LANAddressTests.swift"
        ).read_text(encoding="utf-8")
        for ip, _, _ in LAN_FIXTURES:
            self.assertIn(f'"{ip}"', swift, f"Swift tests should sample {ip}")

    def test_no_new_parser_in_fixtures(self) -> None:
        tree = ast.parse((ROOT / "scripts" / "lan_fixtures.py").read_text(encoding="utf-8"))
        funcs = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
        self.assertNotIn("is_private", funcs)
        self.assertNotIn("is_private_ipv4", funcs)


if __name__ == "__main__":
    unittest.main()
