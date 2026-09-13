#!/usr/bin/env python3
"""Stdlib unit tests for magicpad_proto (binary frames, WS mask, Origin policy)."""
from __future__ import annotations

import json
import os
import struct
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    ALLOWED_OPCODES,
    MAX_FRAME_BYTES,
    MAX_HEADER_BYTES,
    MAX_TYPE_CHARS,
    MAX_VOICE_CHARS,
    PROTO,
    cors_allow_origin,
    decode_frame13,
    decode_frame18,
    decode_latency_echo,
    frame13,
    frame18,
    header_value,
    hello_payload,
    html_escape,
    is_private_ipv4,
    mask_frame,
    origin_allowed,
    sanitize_filename,
    unmask_frame,
)


class Frame13Tests(unittest.TestCase):
    def test_length_and_le_dx_neg1(self):
        b = bytearray(frame13(1, dx=-1, dy=2, buttons=1))
        struct.pack_into("<I", b, 7, 0xA1B2C3D4)
        struct.pack_into("<H", b, 11, 0xBEEF)
        data = bytes(b)
        self.assertEqual(len(data), 13)
        self.assertEqual(data[1:3], b"\xff\xff")  # dx=-1 little-endian
        d = decode_frame13(data)
        self.assertEqual(d["phase"], 1)
        self.assertEqual(d["dx"], -1)
        self.assertEqual(d["dy"], 2)
        self.assertEqual(d["buttons"], 1)
        self.assertEqual(d["t_ms"], 0xA1B2C3D4)
        self.assertEqual(d["seq"], 0xBEEF)


class Frame18Tests(unittest.TestCase):
    def test_fields(self):
        data = frame18(21, fingers=2, gesture=3, ext=1500)
        self.assertEqual(len(data), 18)
        d = decode_frame18(data)
        self.assertEqual(d["phase"], 21)
        self.assertEqual(d["fingers"], 2)
        self.assertEqual(d["gesture"], 3)
        self.assertEqual(d["ext"], 1500)


class MaskTests(unittest.TestCase):
    def test_roundtrip_lengths(self):
        for n in (0, 125, 126, 65535, 65536):
            payload = bytes((i * 17) % 256 for i in range(min(n, 64))) + (b"x" * max(0, n - 64))
            if n > 64:
                payload = os.urandom(n) if n <= 65536 else payload
            if n in (65535, 65536):
                payload = b"\x00" * n
            frame = mask_frame(0x2, payload)
            op, out = unmask_frame(frame)
            self.assertEqual(op, 0x2, msg=f"n={n}")
            self.assertEqual(out, payload, msg=f"n={n}")


class LatencyEchoTests(unittest.TestCase):
    def test_decode(self):
        seq, t_ms = 0x1234, 0x89ABCDEF
        buf = bytes([seq & 0xFF, (seq >> 8) & 0xFF,
                     t_ms & 0xFF, (t_ms >> 8) & 0xFF, (t_ms >> 16) & 0xFF, (t_ms >> 24) & 0xFF])
        d = decode_latency_echo(buf)
        self.assertEqual(d["seq"], seq)
        self.assertEqual(d["t_ms"], t_ms)


class HelloTests(unittest.TestCase):
    def test_shape(self):
        h = hello_payload("smoke-ws", 42.5)
        self.assertEqual(h["type"], "hello")
        self.assertEqual(h["ua"], "smoke-ws")
        self.assertEqual(h["ts"], 42.5)


class OriginPolicyTests(unittest.TestCase):
    def test_shared_vectors(self):
        path = os.path.join(HERE, "fixtures", "origin-vectors.json")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        default_lan = data["lan"]
        for row in data["vectors"]:
            lan = row["lan"] if "lan" in row else default_lan
            got = origin_allowed(row["origin"], lan)
            self.assertEqual(
                got,
                row["allow"],
                f"{row['id']}: origin={row['origin']!r} lan={lan!r} got {got}",
            )

    def test_every_fixture_origin_appears_in_swift(self):
        """The Swift table is hand-copied. Linux CI can still catch a missing vector."""
        path = os.path.join(HERE, "fixtures", "origin-vectors.json")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        swift_path = os.path.join(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Tests",
            "MagicPadServerTests",
            "OriginPolicyTests.swift",
        )
        with open(swift_path, encoding="utf-8") as fh:
            swift = fh.read()
        missing = []
        for row in data["vectors"]:
            origin = row["origin"]
            if origin is None:
                continue
            if origin not in swift:
                missing.append(f"{row['id']}: {origin!r}")
        self.assertFalse(
            missing,
            "origin-vectors.json rows missing from OriginPolicyTests.swift "
            "(add these strings to the hand-copied Swift table):\n  "
            + "\n  ".join(missing),
        )


class HeaderValueTests(unittest.TestCase):
    def test_missing_is_none(self):
        self.assertIsNone(header_value("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", "origin"))

    def test_present(self):
        blob = "GET / HTTP/1.1\r\nOrigin: http://evil.example\r\n\r\n"
        self.assertEqual(header_value(blob, "origin"), "http://evil.example")

    def test_empty_value_is_empty_string(self):
        blob = "GET / HTTP/1.1\r\nOrigin:\r\n\r\n"
        self.assertEqual(header_value(blob, "origin"), "")
        self.assertTrue(origin_allowed(header_value(blob, "origin"), []))


class SmokeWsArgTests(unittest.TestCase):
    def test_expect_reject_flag(self):
        import importlib.util

        path = os.path.join(HERE, "smoke-ws.py")
        spec = importlib.util.spec_from_file_location("smoke_ws", path)
        mod = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(mod)
        args = mod.parse_args(["--origin", "http://evil.example", "--expect-reject"])
        self.assertTrue(args.expect_reject)
        self.assertEqual(args.origin, "http://evil.example")
        args2 = mod.parse_args([])
        self.assertFalse(args2.expect_reject)


class RepoIntegrityTests(unittest.TestCase):
    def test_live_tree_passes(self):
        from repo_integrity import check

        root = os.path.dirname(HERE)
        self.assertEqual(check(root), [])

    def test_remote_stub_is_140_bytes(self):
        from repo_integrity import PLACEHOLDER_MARK, REMOTE_WS_STUB

        self.assertEqual(len(REMOTE_WS_STUB), 140)
        self.assertIn(PLACEHOLDER_MARK.encode("utf-8"), REMOTE_WS_STUB)

    def test_today_stub_would_fail_gate(self):
        from repo_integrity import PLACEHOLDER_MARK, stub_issues

        root = os.path.dirname(HERE)
        issues = stub_issues(root)
        self.assertTrue(
            any("WebSocketServer.swift" in i and "bytes" in i for i in issues),
            msg=issues,
        )
        self.assertTrue(any(PLACEHOLDER_MARK in i for i in issues), msg=issues)
        self.assertTrue(any("500" in i or "lines" in i for i in issues), msg=issues)


class ProtocolLimitsTests(unittest.TestCase):
    def test_caps_match_core(self):
        self.assertEqual(MAX_FRAME_BYTES, 1_048_576)
        self.assertEqual(MAX_HEADER_BYTES, 16_384)
        self.assertEqual(MAX_TYPE_CHARS, 2000)
        self.assertEqual(MAX_VOICE_CHARS, 20_000)
        self.assertEqual(PROTO, 1)
        self.assertEqual(ALLOWED_OPCODES, frozenset({0x1, 0x2, 0x8, 0x9, 0xA}))


class HTMLEscapeTests(unittest.TestCase):
    def test_markup(self):
        self.assertEqual(
            html_escape("<img src=x onerror=alert(1)>"),
            "&lt;img src=x onerror=alert(1)&gt;",
        )
        self.assertEqual(html_escape("a&b"), "a&amp;b")
        self.assertEqual(html_escape("<>&"), "&lt;&gt;&amp;")


class CORSPolicyTests(unittest.TestCase):
    def test_star_and_echo_and_omit(self):
        lan = ["10.8.0.2"]  # example-ip
        self.assertEqual(cors_allow_origin(None, lan), "*")
        self.assertEqual(cors_allow_origin("", lan), "*")
        self.assertEqual(cors_allow_origin("http://127.0.0.1:7878", lan), "http://127.0.0.1:7878")
        self.assertIsNone(cors_allow_origin("http://evil.example", lan))


class LANAddressTests(unittest.TestCase):
    def test_rfc1918(self):
        self.assertTrue(is_private_ipv4("10.8.0.2"))  # example-ip
        self.assertTrue(is_private_ipv4("192.168.1.5"))  # example-ip
        self.assertFalse(is_private_ipv4("127.0.0.1"))
        self.assertFalse(is_private_ipv4("8.8.8.8"))


class FilenamesTests(unittest.TestCase):
    def test_sanitize(self):
        self.assertEqual(sanitize_filename("../../etc/passwd"), "passwd")
        self.assertEqual(sanitize_filename("a<>b.txt"), "a__b.txt")
        self.assertEqual(sanitize_filename("."), "magicpad-file.bin")


class FixtureTests(unittest.TestCase):
    def test_key_aliases_self_consistent(self):
        path = os.path.join(HERE, "fixtures", "key-aliases.json")
        with open(path, encoding="utf-8") as f:
            data = json.loads(f.read())
        allowed = set(data["allowed"])
        inputs = []
        for row in data["aliases"]:
            self.assertIn("input", row)
            self.assertIn("canonical", row)
            self.assertIn(row["canonical"], allowed, msg=row)
            inputs.append(row["input"])
        self.assertEqual(len(inputs), len(set(inputs)), "duplicate alias inputs")


if __name__ == "__main__":
    unittest.main()
