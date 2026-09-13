#!/usr/bin/env python3
"""Stdlib unit tests for magicpad_proto (binary frames, WS mask, Origin policy)."""
from __future__ import annotations

import json
import os
import re
import struct
import sys
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from magicpad_proto import (  # noqa: E402
    PAIRING_ENV,
    PAIRING_HELLO_FIELD,
    PAIRING_REJECTED,
    ALLOWED_OPCODES,
    CERT_CONTENT_TYPE,
    CERT_FILENAME,
    CERT_FORBIDDEN_BODY,
    CERT_MISSING_BODY,
    CERT_PATH,
    CLOSE_MESSAGE_TOO_BIG,
    CLOSE_UNSUPPORTED_DATA,
    ERROR_PAGE_CSP,
    JSON_BURST,
    JSON_TOKENS_PER_SEC,
    JSONRateLimit,
    MAX_CLIENTS,
    MAX_FRAME_BYTES,
    MAX_HEADER_BYTES,
    MAX_TYPE_CHARS,
    MAX_VOICE_CHARS,
    METERED_JSON_TYPES,
    PAIRING_ENV,
    PAIRING_HELLO_FIELD,
    PAIRING_REJECTED,
    PROTO,
    cert_allows_get,
    pairing_allows,
    qr_url_is_safe,
    cert_refuses_secret,
    cors_allow,
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
    json_text_encode,
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
