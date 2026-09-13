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
    decode_frame13,
    decode_frame18,
    decode_latency_echo,
    frame13,
    frame18,
    hello_payload,
    mask_frame,
    origin_allowed,
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
    def test_table(self):
        lan = ["10.8.0.2"]  # example-ip
        self.assertTrue(origin_allowed(None, lan))
        self.assertTrue(origin_allowed("", lan))
        self.assertTrue(origin_allowed("http://127.0.0.1:7878", lan))
        self.assertTrue(origin_allowed("https://localhost:7879", lan))
        self.assertTrue(origin_allowed("http://[::1]:7878", lan))
        self.assertTrue(origin_allowed("http://10.8.0.2:7878", lan))  # example-ip
        self.assertFalse(origin_allowed("http://evil.example", lan))
        self.assertFalse(origin_allowed("http://10.8.0.99:7878", lan))  # example-ip not in list
        self.assertFalse(origin_allowed("null", lan))


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
