#!/usr/bin/env python3
"""MagicPad binary + WS helpers (stdlib). Shared by smoke-ws.py and test-protocol.py."""
from __future__ import annotations

import json
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


def parse_binary_frame(data: bytes | None) -> dict | None:
    """Cycle 26: Core BinaryFrame.parse mirror. <7 bytes → None (no inject)."""
    if data is None or len(data) < 7:
        return None
    phase = data[0]
    dx = struct.unpack_from("<h", data, 1)[0]
    dy = struct.unpack_from("<h", data, 3)[0]
    pressure = data[5]
    buttons = data[6]
    t_ms = 0
    seq = 0
    if len(data) >= 13:
        t_ms = struct.unpack_from("<I", data, 7)[0]
        seq = struct.unpack_from("<H", data, 11)[0]
    fingers = 1
    gesture = 0
    ext = 0
    if len(data) >= 18:
        fingers = data[13]
        gesture = data[14]
        ext = struct.unpack_from("<h", data, 15)[0]
    return {
        "phase": phase,
        "dx": dx,
        "dy": dy,
        "pressure": pressure,
        "buttons": buttons,
        "t_ms": t_ms,
        "seq": seq,
        "fingers": fingers,
        "gesture": gesture,
        "ext": ext,
        "kind": PHASES.get(phase, "unknown"),
        "byte_count": len(data),
        "is_gesture": phase >= 10,
    }


def hello_payload(ua: str, ts: float) -> dict:
    return {"type": "hello", "ua": ua, "ts": ts, "proto": PROTO}


def header_value(blob: str, name: str) -> str | None:
    """Mirror of MagicPadCore.HTTPHeaderValue.first.

    Present-but-empty (`Origin:\\r\\n`) → `\"\"`, not the header name.
    Missing → None.
    """
    target = name.lower() + ":"
    normalized = blob.replace("\r\n", "\n").replace("\r", "\n")
    for line in normalized.split("\n"):
        if line.lower().startswith(target):
            parts = line.split(":", 1)
            if len(parts) < 2:
                return ""
            return parts[1].strip()
    return None


def origin_parse(origin: str) -> tuple[str, str] | None:
    """Mirror of MagicPadCore.OriginPolicy.parse. None → reject."""
    trimmed = origin.strip()
    if not trimmed or trimmed.lower() == "null":
        return None
    while trimmed.endswith("/"):
        trimmed = trimmed[:-1]
    parsed = urlparse(trimmed)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https", "ws", "wss"):
        return None
    # urlparse.query / .fragment are always str ('' when absent). Swift
    # URLComponents returns nil when absent and "" when present-but-empty
    # (http://host/# and http://host?). Reject on the raw characters so
    # both sides match. username/password are None when absent and "" when
    # present-but-empty (http://@host) — test `is not None`, not truthiness.
    if "?" in trimmed or "#" in trimmed:
        return None
    if parsed.username is not None or parsed.password is not None:
        return None
    path = parsed.path or ""
    if path not in ("", "/"):
        return None
    netloc = parsed.netloc or ""
    if "@" in netloc:
        netloc = netloc.rsplit("@", 1)[-1]
    if "%" in netloc:
        return None
    host = (parsed.hostname or "").lower()
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    if not host:
        return None
    return scheme, host


def origin_allowed(origin: str | None, lan_ips: list[str] | None = None) -> bool:
    """Mirror of MagicPadCore.OriginPolicy.isAllowed (MP-01)."""
    if origin is None:
        return True
    trimmed = origin.strip()
    if not trimmed:
        return True
    if trimmed.lower() == "null":
        return False
    parsed = origin_parse(trimmed)
    if parsed is None:
        return False
    _scheme, host = parsed
    allowed = {"127.0.0.1", "localhost", "::1"}
    for ip in lan_ips or []:
        h = str(ip).strip().lower().strip("[]")
        if h:
            allowed.add(h)
    return host in allowed


# Mirror of MagicPadCore.ProtocolLimits / HTMLEscape / CORSPolicy / LANAddress / Filenames.
MAX_FRAME_BYTES = 1_048_576
MAX_HEADER_BYTES = 16_384
MAX_TYPE_CHARS = 2000
MAX_VOICE_CHARS = 20_000
PROTO = 1
REQUIRED_WS_VERSION = "13"
ALLOWED_OPCODES = frozenset({0x0, 0x1, 0x2, 0x8, 0x9, 0xA})
CLOSE_MESSAGE_TOO_BIG = 1009
CLOSE_UNSUPPORTED_DATA = 1003
MAX_CLIENTS = 8
JSON_TOKENS_PER_SEC = 40
JSON_BURST = 80
METERED_JSON_TYPES = frozenset({"type", "text", "voice"})
ERROR_PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'"


class JSONRateLimit:
    """Mirror of MagicPadCore.JSONRateLimit. Meters type/text/voice only."""

    def __init__(
        self,
        tokens_per_sec: float = JSON_TOKENS_PER_SEC,
        burst: float = JSON_BURST,
    ) -> None:
        self.tokens_per_sec = tokens_per_sec
        self.burst = burst
        self.tokens = float(burst)
        self.last_refill = 0.0

    def allow(self, typ: str, now: float | None = None) -> bool:
        if typ not in METERED_JSON_TYPES:
            return True
        if now is None:
            now = 0.0
        if self.last_refill == 0.0:
            self.last_refill = now
        dt = max(0.0, now - self.last_refill)
        self.tokens = min(self.burst, self.tokens + dt * self.tokens_per_sec)
        self.last_refill = now
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True

    def reset(self, now: float = 0.0) -> None:
        self.tokens = float(self.burst)
        self.last_refill = now


def json_text_encode(obj: dict) -> str | None:
    """Mirror of JSONText.encode: sorted keys, compact, no escaped slashes."""
    try:
        return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    except (TypeError, ValueError):
        return None


def html_escape(raw: str) -> str:
    out: list[str] = []
    for ch in raw:
        if ch == "&":
            out.append("&amp;")
        elif ch == "<":
            out.append("&lt;")
        elif ch == ">":
            out.append("&gt;")
        elif ch == '"':
            out.append("&quot;")
        elif ch == "'":
            out.append("&#39;")
        else:
            out.append(ch)
    return "".join(out)


def cors_allow(origin: str | None, lan_ips: list[str] | None = None) -> tuple[str, bool] | None:
    """Mirror of CORSPolicy.accessControl. None → omit ACAO.

    Returns (allowOrigin, needsVary). `*` has needsVary False.
    """
    if origin is None:
        return ("*", False)
    trimmed = origin.strip()
    if not trimmed:
        return ("*", False)
    if origin_allowed(origin, lan_ips):
        return (trimmed, True)
    return None


def cors_allow_origin(origin: str | None, lan_ips: list[str] | None = None) -> str | None:
    got = cors_allow(origin, lan_ips)
    return None if got is None else got[0]


def is_private_ipv4(ip: str) -> bool:
    parts = ip.split(".")
    if len(parts) != 4:
        return False
    # One to three ASCII digits. Reject sign / underscore / Unicode digits
    # that Python int() or Swift Int(String) would accept (Opus C7 M6).
    if any((not p.isascii()) or (not p.isdigit()) or not (1 <= len(p) <= 3) for p in parts):
        return False
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return False
    if any(n < 0 or n > 255 for n in nums):
        return False
    if nums[0] == 127:
        return False
    if nums[0] == 169 and nums[1] == 254:
        return False
    if nums[0] == 192 and nums[1] == 168:
        return True
    if nums[0] == 10:
        return True
    if nums[0] == 172 and 16 <= nums[1] <= 31:
        return True
    return False


def sanitize_filename(raw: str) -> str:
    import os
    import unicodedata

    name = raw.strip().replace("\\", "/").rstrip("/")
    name = os.path.basename(name)
    name = unicodedata.normalize("NFC", name)
    # Swift CharacterSet.alphanumerics includes Mn. Keep combining marks
    # that have no NFC precomposed form (Opus C7 §5 residual).
    def _keep(ch: str) -> bool:
        return ch.isalnum() or ch in "._- ()[]" or unicodedata.category(ch) == "Mn"

    name = "".join(ch if _keep(ch) else "_" for ch in name)
    if len(name) > 120:
        root, ext = os.path.splitext(name)
        if ext:
            keep = max(1, 120 - len(ext))
            name = root[:keep] + ext
            if len(name) > 120:
                name = name[:120]
        else:
            name = name[:120]
    if not name or name in {".", "..", "..."}:
        return "magicpad-file.bin"
    return name


# Cycle 36: documented HTTP routes. classify is WS-only (not in this set).
HTTP_ROUTES = ("/", "/health", "/stt", "/drop", "/cert")
HTTP_ROUTE_COUNT = 5

CERT_PATH = "/cert"
CERT_FILENAME = "magicpad-lan.cer"
CERT_CONTENT_TYPE = "application/x-x509-ca-cert"
CERT_MISSING_BODY = "cert_not_ready"
CERT_FORBIDDEN_BODY = "cert_forbidden"
CERT_REFUSED_SUFFIXES = (".pem", ".p12", ".key")


def cert_normalized_path(raw: str) -> str:
    """Mirror of CertRoute.normalizedPath — query and trailing slash stripped."""
    from urllib.parse import unquote

    clean = (raw or "").split("?", 1)[0]
    clean = unquote(clean).strip()
    while len(clean) > 1 and clean.endswith("/"):
        clean = clean[:-1]
    return clean or "/"


def is_documented_http_path(raw: str) -> bool:
    """Cycle 37: only PROTOCOL HTTP routes. classify / pair are not routes."""
    return cert_normalized_path(raw) in HTTP_ROUTES


def cert_allows_get(raw: str) -> bool:
    return cert_normalized_path(raw) == CERT_PATH


def cert_refuses_secret(raw: str) -> bool:
    p = cert_normalized_path(raw).lower()
    return any(p.endswith(s) for s in CERT_REFUSED_SUFFIXES)


STT_START = frozenset({"start", "begin", "on"})
STT_STOP = frozenset({"stop", "end", "off"})
STT_STATUS = frozenset({"status"})


STT_LANGS = frozenset({"zh-CN", "en-US", "ja-JP"})
STT_LANG_FALLBACK = "zh-CN"


WS_TYPES = frozenset(
    {"voice", "key", "type", "text", "stt", "hello", "ping", "classify"}
)


def ws_types_are_names_not_paths() -> bool:
    """Cycle 39: WS types are JSON type strings, not HTTP paths."""
    return all("/" not in name for name in WS_TYPES)


CLASSIFY_INJECTS = False
CLASSIFY_IS_HEALTH_KEY = False
CLASSIFY_HTTP_PATH = None


def parse_classify_kind(raw: str | None) -> str | None:
    """Cycle 30: Core Classify.parseKind mirror. Empty → None. Never injects."""
    key = (raw or "").strip()
    return key or None


def parse_ws_type(raw: str | None) -> str | None:
    """Cycle 27: Core WSType.parse mirror. Exact type string; else None."""
    key = (raw or "").strip()
    if key in WS_TYPES:
        return key
    return None


def parse_stt_on_device(value: object | None) -> bool:
    """Cycle 25: Core STTOnDevice.parse mirror. JSON bool only; else true."""
    if isinstance(value, bool):
        return value
    return True


def parse_stt_lang(raw: str | None) -> str:
    """Cycle 24: Core STTLang.parse mirror. Unknown → zh-CN."""
    key = (raw or "").strip()
    if key in STT_LANGS:
        return key
    return STT_LANG_FALLBACK


def parse_stt_action(raw: str | None) -> str | None:
    """Cycle 23: Core STTAction.parse mirror. Unknown → None (bad_action)."""
    key = (raw or "").strip().lower()
    if key in STT_START:
        return "start"
    if key in STT_STOP:
        return "stop"
    if key in STT_STATUS:
        return "status"
    return None


PAIRING_ENV = "MAGICPAD_PAIRING_TOKEN"
PAIRING_HELLO_FIELD = "pair"
PAIRING_REJECTED = "pairing_rejected"
FORBIDDEN_HEALTH_KEYS = frozenset({PAIRING_HELLO_FIELD, PAIRING_ENV, "classify"})


def health_allows_key(key: str) -> bool:
    """Cycle 29: pairing hatch is hello-only. Never a /health key."""
    return key not in FORBIDDEN_HEALTH_KEYS


def pairing_configured(env: dict[str, str] | None = None) -> str | None:
    import os

    raw = (env if env is not None else os.environ).get(PAIRING_ENV, "")
    v = str(raw).strip()
    return v or None


def pairing_allows(provided: str | None, configured: str | None = None) -> bool:
    """Off (configured empty/None) → allow. On → hello.pair must match."""
    want = configured
    if want is None:
        want = pairing_configured()
    if not want:
        return True
    got = (provided or "").strip()
    return got == want


def qr_url_is_safe(url: str, configured: str | None = None) -> bool:
    """Cycle 21/22: QR / --print-only must never carry the pairing hatch."""
    from urllib.parse import parse_qsl, urlsplit

    if "pair=" in url.lower():
        return False
    if "classify=" in url.lower():
        return False
    if PAIRING_ENV in url:
        return False
    token = configured
    if token is None:
        token = pairing_configured() or ""
    token = (token or "").strip()
    if token and token in url:
        return False
    parts = urlsplit(url)
    for key, _val in parse_qsl(parts.query, keep_blank_values=True):
        if key.lower() == PAIRING_HELLO_FIELD:
            return False
        if key.lower() == "classify":
            return False
    if "pair=" in (parts.fragment or "").lower():
        return False
    if "classify=" in (parts.fragment or "").lower():
        return False
    return True
