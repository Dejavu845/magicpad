#!/usr/bin/env python3
"""Cycle 35: generate_qr --print-only never emits classify=."""

from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = Path(HERE).resolve().parent
sys.path.insert(0, HERE)

from generate_qr import build_qr_url  # noqa: E402
from magicpad_proto import qr_url_is_safe  # noqa: E402


class Cycle35PrintOnlyTests(unittest.TestCase):
    def test_print_only_stdout_omits_classify(self) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "generate_qr.py"),
                "10.8.0.2",  # example-ip
                "--print-only",
                "--http",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        self.assertNotIn("classify=", out.lower())
        self.assertNotIn("pair=", out.lower())
        self.assertTrue(out.strip())

    def test_build_qr_url_still_safe(self) -> None:
        url = build_qr_url("http", "10.8.0.2", 7878, auto=True)  # example-ip
        self.assertTrue(qr_url_is_safe(url, configured=""))
        self.assertNotIn("classify=", url.lower())

    def test_generate_qr_scans_sources_for_classify(self) -> None:
        text = (ROOT / "scripts" / "generate_qr.py").read_text(encoding="utf-8")
        self.assertIn('if "classify=" in body.lower():', text)


if __name__ == "__main__":
    unittest.main()
