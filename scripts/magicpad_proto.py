#!/usr/bin/env python3
"""MagicPad binary + WS helpers (stdlib). Shared by smoke-ws.py and test-protocol.py."""
from __future__ import annotations

import os
import struct
from urllib.parse import urlparse

PHASES = {
    0: "down",
    1: "move",
    2: "up",
    3: "cancel",
    10: "dbl",
    11: "right",
    20: "scroll",
    21: "pinch",
    22: "triple",
    23: "smartzoom",
    24: "mission",
}


def mask_frame(opcode: int, data: bytes) -> bytes:
    mask = os.urandom(4)
    bl = len(data)
    if bl < 126:
        hdr = bytes([0x80 | opcode, 0x80 | bl]) + mask
    elif bl < 65536:
        hdr = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack(">H", bl) + mask
    else:
        hdr = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack(">Q", bl) + mask
    body = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return hdr + body


def unmask_frame(frame: bytes) -> tuple[int, bytes]:
    """Return (opcode, payload) from a single complete WS frame (masked or not)."""
    if len(frame) < 2:
        raise ValueError("short frame")
    opcode = frame[0] & 0x0F
    masked = (frame[1] & 0x80) != 0
    ln = frame[1] & 0x7F
    off = 2
    if ln == 126:
        ln = struct.unpack(">H", frame[off : off + 2])[0]
        off += 2
    elif ln == 127:
        ln = struct.unpack(">Q", frame[off : off + 8])[0]
        off += 8
    mask = b""
    if masked:
        mask = frame[off : off + 4]
        off += 4
    payload = bytearray(frame[off : off + ln])
    if masked:
        payload = bytearray(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, bytes(payload)


def frame13(phase: int, dx: int = 0, dy: int = 0, buttons: int = 0) -> bytes:
    buf = bytearray(13)
    buf[0] = phase & 0xFF
    struct.pack_into("<h", buf, 1, dx)
    struct.pack_into("<h", buf, 3, dy)
    buf[6] = buttons & 0xFF
    return bytes(buf)


def frame18(phase: int, fingers: int = 1, gesture: int = 0, ext: int = 0) -> bytes:
    buf = bytearray(18)
    buf[0] = phase & 0xFF
    buf[13] = fingers & 0xFF
    buf[14] = gesture & 0xFF
    struct.pack_into("<h", buf, 15, ext)
    return bytes(buf)


def decode_frame13(data: bytes) -> dict:
    if len(data) < 13:
        raise ValueError("frame13 requires 13 bytes")
    phase = data[0]
    dx = struct.unpack_from("<h", data, 1)[0]
    dy = struct.unpack_from("<h", data, 3)[0]
    pressure = data[5]
    buttons = data[6]
    t_ms = struct.unpack_from("<I", data, 7)[0]
    seq = struct.unpack_from("<H", data, 11)[0]
    return {
        "phase": phase,
        "dx": dx,
        "dy": dy,
        "pressure": pressure,
        "buttons": buttons,
        "t_ms": t_ms,
        "seq": seq,
        "kind": PHASES.get(phase, "unknown"),
    }


def decode_frame18(data: bytes) -> dict:
    if len(data) < 18:
        raise ValueError("frame18 requires 18 bytes")
    out = decode_frame13(data[:13])
    out["fingers"] = data[13]
    out["gesture"] = data[14]
    out["ext"] = struct.unpack_from("<h", data, 15)[0]
    return out


def decode_latency_echo(data: bytes) -> dict:
    """6 bytes: seq_lo, seq_hi, t_ms little-endian u32."""
    if len(data) < 6:
        raise ValueError("latency echo requires 6 bytes")
    seq = data[0] | (data[1] << 8)
    t_ms = data[2] | (data[3] << 8) | (data[4] << 16) | (data[5] << 24)
    return {"seq": seq, "t_ms": t_ms}


def hello_payload(ua: str, ts: float) -> dict:
    return {"type": "hello", "ua": ua, "ts": ts}


def origin_allowed(origin: str | None, lan_ips: list[str] | None = None) -> bool:
    """Mirror of MagicPadCore.OriginPolicy.isAllowed (MP-01)."""
    if origin is None or origin == "":
        return True
    trimmed = origin.strip()
    if not trimmed:
        return True
    if trimmed.lower() == "null":
        return False
    while trimmed.endswith("/"):
        trimmed = trimmed[:-1]
    parsed = urlparse(trimmed)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https", "ws", "wss"):
        return False
    host = (parsed.hostname or "").lower()
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    allowed = {"127.0.0.1", "localhost", "::1"}
    for ip in lan_ips or []:
        allowed.add(str(ip).strip().lower().strip("[]"))
    return host in allowed
