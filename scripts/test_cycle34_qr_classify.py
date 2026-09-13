#!/usr/bin/env python3
"""Cycle 34: QR / --print-only must never carry a classify query."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from generate_qr import build_qr_url  # noqa: E402
from magicpad_proto import qr_url_is_safe  # noqa: E402


class Cycle34QRNeverClassifyTests(unittest.TestCase):
    def test_python_rejects_classify_query(self) -> None:
        self.assertTrue(
            qr_url_is_safe("http://10.8.0.2:7878/?auto=1&host=10.8.0.2", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?classify=1", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?auto=1&classify=", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/#classify=x", configured="")  # example-ip
        )

    def test_build_qr_url_has_no_classify(self) -> None:
        url = build_qr_url("http", "10.8.0.2", 7878, auto=True)  # example-ip
        self.assertTrue(qr_url_is_safe(url, configured=""))
        self.assertNotIn("classify", url.lower())

    def test_swift_rejects_classify_equals(self) -> None:
        pairing = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "PairingToken.swift",
        ).read_text(encoding="utf-8")
        self.assertIn('lowered.contains("classify=")', pairing)
        classify = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadCore",
            "Classify.swift",
        ).read_text(encoding="utf-8")
        self.assertIn("public static let qrQueryKey = jsonType", classify)


if __name__ == "__main__":
    unittest.main()
