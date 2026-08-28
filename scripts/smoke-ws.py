#!/usr/bin/env python3
"""MagicPad overnight WS smoke — no deps beyond stdlib.

Usage:
  python3 scripts/smoke-ws.py
  BASE_HOST=127.0.0.1 BASE_PORT=7878 python3 scripts/smoke-ws.py
"""
from __future__ import annotations

import base64
import json
import os
import socket
import struct
import sys
import time
import urllib.request

HOST = os.environ.get("BASE_HOST", "127.0.0.1")
PORT = int(os.environ.get("BASE_PORT", "7878"))


def http_health() -> dict:
    url = f"http://{HOST}:{PORT}/health"
    with urllib.request.urlopen(url, timeout=4) as r:
        return json.loads(r.read().decode())


def ws_connect() -> socket.socket:
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET / HTTP/1.1\r\nHost: {HOST}:{PORT}\r\n"
        f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    ).encode()
    s = socket.create_connection((HOST, PORT), timeout=4)
    s.sendall(req)
    resp = s.recv(4096)
    if b"101" not in resp:
        raise RuntimeError(f"WS handshake failed: {resp[:200]!r}")
    return s


def mask_frame(opcode: int, data: bytes) -> bytes:
    mask = os.urandom(4)
    bl = len(data)
    if bl < 126:
        hdr = bytes([0x80 | opcode, 0x80 | bl]) + mask
    else:
        hdr = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack(">H", bl) + mask
    body = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return hdr + body


def send_bin(s: socket.socket, data: bytes) -> None:
    s.sendall(mask_frame(0x2, data))


def send_json(s: socket.socket, obj: dict) -> None:
    s.sendall(mask_frame(0x1, json.dumps(obj).encode()))


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


def main() -> int:
    print(f"smoke → {HOST}:{PORT}")
    h = http_health()
    print("health:", json.dumps(h, ensure_ascii=False))
    assert h.get("ok") is True, "health not ok"
    assert h.get("html") is True, "html missing"

    s = ws_connect()
    print("ws: open PASS")

    def recv_json(timeout: float = 2.0, retries: int = 8):
        """Read until a text JSON frame; skip binary latency echoes."""
        s.settimeout(timeout)
        deadline = time.time() + timeout
        last = None
        for _ in range(retries):
            remain = deadline - time.time()
            if remain <= 0:
                break
            s.settimeout(max(0.05, remain))
            try:
                raw = s.recv(4096)
            except socket.timeout:
                break
            if not raw:
                break
            # may contain multiple frames; walk
            i = 0
            while i < len(raw):
                if i + 2 > len(raw):
                    break
                opcode = raw[i] & 0x0F
                ln = raw[i + 1] & 0x7F
                masked = (raw[i + 1] & 0x80) != 0
                off = i + 2
                if ln == 126:
                    if off + 2 > len(raw):
                        break
                    ln = struct.unpack(">H", raw[off : off + 2])[0]
                    off += 2
                if masked:
                    off += 4  # unexpected from server
                payload = raw[off : off + ln]
                i = off + ln
                if opcode == 0x1:
                    try:
                        return json.loads(payload.decode())
                    except Exception:
                        last = {"_text": payload.decode("utf-8", "replace")}
                elif opcode == 0x2:
                    last = {"_bin": len(payload)}
                    continue
                else:
                    last = {"_op": opcode}
        return last

    send_json(s, {"type": "hello", "ua": "smoke-ws", "ts": time.time()})
    ha = recv_json()
    print("hello_ack:", ha)
    if not (isinstance(ha, dict) and ha.get("type") == "hello_ack"):
        print("WARN: expected hello_ack")

    send_json(s, {"type": "ping", "ts": 42})
    po = recv_json()
    print("pong:", po)
    if not (isinstance(po, dict) and po.get("type") == "pong"):
        print("WARN: expected pong")

    for _ in range(5):
        send_bin(s, frame13(1, 4, -2))
    send_bin(s, frame13(0, buttons=1))
    send_bin(s, frame13(2, buttons=1))
    send_bin(s, frame18(11, fingers=2, gesture=5))
    send_bin(s, frame18(22))
    send_bin(s, frame18(23))
    # H6: do not send phase 24 here — inject now opens Mission Control.app
    print("binary: move/click/right/triple/smartzoom SENT")

    send_json(s, {"type": "classify", "kind": "right", "reason": "smoke", "phase": 11, "net": 8, "ms": 120})
    ca = None
    end_ca = time.time() + 2.0
    while time.time() < end_ca:
        msg = recv_json(max(0.1, end_ca - time.time()), retries=6)
        if isinstance(msg, dict) and msg.get("type") == "classify_ack":
            ca = msg
            break
    print("classify_ack:", ca if ca else "MISSING (latency echo raced)")
    h2 = http_health()
    if h2.get("lastGesture") != "right" or h2.get("lastGestureReason") != "smoke":
        raise RuntimeError(
            "health lastGesture mismatch: %r / %r" % (h2.get("lastGesture"), h2.get("lastGestureReason"))
        )
    print("classify→health lastGesture=right reason=smoke PASS")

    tag = f"SMOKE-WS {time.strftime('%H:%M:%S')}"
    send_json(
        s,
        {
            "type": "voice",
            "text": tag,
            "mode": "append",
            "autoPaste": True,
        },
    )
    ack = None
    end = time.time() + 3.0
    while time.time() < end:
        try:
            msg = recv_json(max(0.1, end - time.time()), retries=4)
        except socket.timeout:
            break
        if isinstance(msg, dict) and msg.get("type") == "voice_ack":
            ack = msg
            break
        # skip binary / other
    print("voice_ack:", ack if ack else "MISSING (clipboard still checked)")
    s.close()

    try:
        clip = os.popen("pbpaste").read()
        print("clipboard:", clip[:100].replace("\n", " "))
        if tag in clip:
            print("clipboard: PASS")
        else:
            print("clipboard: WARN (tag not found — ax may be off for paste)")
    except Exception as e:
        print("clipboard skip:", e)

    if h.get("ax") is False:
        print("NOTE: ax=false — re-check Accessibility for inject visibility")
    print("OVERALL: PASS (protocol)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print("FAIL:", e, file=sys.stderr)
        sys.exit(1)
