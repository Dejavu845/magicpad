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
