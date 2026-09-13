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
