#!/usr/bin/env python3
"""Cycle 21: QR / --print-only must never carry the pairing hatch."""
from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import qr_url_is_safe  # noqa: E402


def _swift_core(name: str) -> str:
    return os.path.join(
        os.path.dirname(HERE),
        "MagicPadServer",
        "Sources",
        "MagicPadCore",
        name,
    )


def _swift_live(text: str) -> str:
    live = []
    for raw in text.splitlines():
        if raw.lstrip().startswith("//"):
            continue
        live.append(raw.split("//")[0])
    return "\n".join(live)


class Cycle21QRNeverEmbedsTokenTests(unittest.TestCase):
    def test_python_helper_rejects_pair_and_env(self):
        self.assertTrue(
            qr_url_is_safe("http://10.8.0.2:7878/?auto=1&host=10.8.0.2", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?pair=secret", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe(
                "http://10.8.0.2:7878/?x=MAGICPAD_PAIRING_TOKEN", configured=""  # example-ip
            )
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?t=secret", configured="secret")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?pair", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/?auto=1&pair=", configured="")  # example-ip
        )
        self.assertFalse(
            qr_url_is_safe("http://10.8.0.2:7878/#pair=secret", configured="")  # example-ip
        )

    def test_generate_qr_print_only_and_pair_flag(self):
        from generate_qr import build_qr_url

        url = build_qr_url("http", "10.8.0.2", 7878, auto=True)  # example-ip
        self.assertNotIn("pair=", url.lower())
        self.assertNotIn("MAGICPAD_PAIRING_TOKEN", url)
        self.assertTrue(url.startswith("http://"))
        env = os.environ.copy()
        env["MAGICPAD_PAIRING_TOKEN"] = "leaked-secret-token"
        proc = subprocess.run(
            [
                sys.executable,
                os.path.join(HERE, "generate_qr.py"),
                "10.8.0.2",  # example-ip
                "--print-only",
                "--http",
            ],
            capture_output=True,
            text=True,
            env=env,
            cwd=os.path.dirname(HERE),
        )
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn("QR URL:", out)
        self.assertNotIn("pair=", out.lower())
        self.assertNotIn("leaked-secret-token", out)
        refused = subprocess.run(
            [
                sys.executable,
                os.path.join(HERE, "generate_qr.py"),
                "10.8.0.2",  # example-ip
                "--print-only",
                "--http",
                "--pair",
                "nope",
            ],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(HERE),
        )
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("never embed", (refused.stdout + refused.stderr).lower())

    def test_protocol_and_swift_lock(self):
        proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("### QR never embeds the token", proto)
        self.assertIn("`--pair` is refused", proto)
        core = Path(_swift_core("PairingToken.swift")).read_text(encoding="utf-8")
        live = _swift_live(core)
        self.assertIn("qrURLIsSafe", live)
        start = proto.find("### `GET /health` keys")
        end = proto.find("\n## ", start + 1)
        health = proto[start:end]
        self.assertNotIn("pair", health)


if __name__ == "__main__":
    unittest.main()
