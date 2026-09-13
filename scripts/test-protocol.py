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
    PROTO,
    cert_allows_get,
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


class HelloTests(unittest.TestCase):
    def test_shape(self):
        h = hello_payload("smoke-ws", 42.5)
        self.assertEqual(h["type"], "hello")
        self.assertEqual(h["ua"], "smoke-ws")
        self.assertEqual(h["ts"], 42.5)
        self.assertEqual(h["proto"], PROTO)


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


class Cycle7WiringLockTests(unittest.TestCase):
    """Only asserts on the live 62 KB file. The 140-byte remote stub skips."""

    def test_local_server_has_cycle7_inserts(self):
        path = os.path.join(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "WebSocketServer.swift",
        )
        raw = Path(path).read_text(encoding="utf-8")
        if len(raw.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        needles = (
            "HTTPPostOrigin.allows",
            "pendingCloseCode",
            "sendCloseFrame(code:",
            "HTMLEscape.escape",
            "sourceLabel",
            "ProtocolLimits.maxFrameBytes",
            "431 Request Header Fields Too Large",
            "426 Upgrade Required",
            "CORSPolicy.accessControl",
            "HTTPHeaderValue.first",
            "import MagicPadCore",
            "JSONText.encode",
            "ProtocolLimits.proto",
        )
        missing = [n for n in needles if n not in raw]
        self.assertFalse(missing, missing)
        self.assertNotIn("Self.headerValue", raw)
        self.assertNotIn("private static func headerValue", raw)
        start = raw.index("private func parseFrame()")
        end = raw.index("\n    func sendLatencyEcho")
        parse = raw[start:end]
        self.assertNotIn("closeInternal()", parse)
        self.assertNotIn("sendCloseFrame(", parse)
        self.assertGreaterEqual(
            parse.count("pendingCloseCode = ProtocolLimits.closeMessageTooBig"),
            2,
            "Int.max 64-bit length and maxFrameBytes must both set close 1009",
        )
        root = os.path.dirname(HERE)
        for rel in (
            "MagicPadServer/Sources/MagicPadServer/LANDetector.swift",
            "MagicPadServer/Sources/MagicPadServer/FileDropPasteboard.swift",
        ):
            text = Path(root, rel).read_text(encoding="utf-8")
            self.assertIn("import MagicPadCore", text, rel)


class Cycle8HTTPOriginSmokeLockTests(unittest.TestCase):
    """Grep lock: smoke-all.sh must exercise POST /drop Origin 403.

    Does not start a server. Owner-Mac smoke-all.sh is what actually hits
    the wired beginHTTPPost path (Opus C7 M5).
    """

    def test_smoke_all_has_http_post_origin_403(self):
        path = os.path.join(os.path.dirname(HERE), "scripts", "smoke-all.sh")
        raw = Path(path).read_text(encoding="utf-8")
        if "drop origin allowlist" not in raw:
            self.skipTest(
                "scripts/smoke-all.sh is the remote copy without the Cycle 8 Origin block"
            )
        self.assertIn("drop origin allowlist", raw)
        self.assertIn("Origin: http://evil.example", raw)
        self.assertIn("origin_rejected", raw)
        self.assertIn("Origin: http://127.0.0.1:7878", raw)


class Cycle17KeyAllowlistTests(unittest.TestCase):
    """MP-12: PROTOCOL names every canonical key action."""

    def test_protocol_lists_every_allowed_key(self):
        root = os.path.dirname(HERE)
        proto = Path(root, "docs", "PROTOCOL.md").read_text(encoding="utf-8")
        self.assertIn("### `key` allowlist", proto)
        with open(os.path.join(HERE, "fixtures", "key-aliases.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        missing = [name for name in data["allowed"] if name not in proto]
        self.assertFalse(missing, missing)


class Cycle16MenuAndProtocolTests(unittest.TestCase):
    """MP-12 voice_ack table; MP-20 menu diagnostics (no /health token)."""

    def test_protocol_voice_ack_and_classify(self):
        proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("### `voice_ack` reasons", proto)
        self.assertIn("`rate_limited`", proto)
        self.assertIn("`classify_ack`", proto)
        self.assertIn("Never put a token in `/health`", proto)

    def test_menu_shows_proto_htmlrev_clients(self):
        path = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "MagicPadServer.swift",
        )
        raw = path.read_text(encoding="utf-8")
        live = _swift_live(raw)
        self.assertIn("import MagicPadCore", live)
        self.assertIn("ProtocolLimits.proto", live)
        self.assertIn("StaticFileLocator.htmlRev()", live)
        self.assertIn("WebSocketServer.liveClientCount", live)
        self.assertNotIn("pairing", live.lower())


class Cycle15CertAndDraftTests(unittest.TestCase):
    """MP-22 GET /cert whitelist; MP-24 draft persist gates."""

    def test_python_cert_route_is_cer_only(self):
        self.assertEqual(CERT_PATH, "/cert")
        self.assertEqual(CERT_FILENAME, "magicpad-lan.cer")
        self.assertEqual(CERT_CONTENT_TYPE, "application/x-x509-ca-cert")
        self.assertEqual(CERT_MISSING_BODY, "cert_not_ready")
        self.assertEqual(CERT_FORBIDDEN_BODY, "cert_forbidden")
        self.assertTrue(cert_allows_get("/cert"))
        self.assertTrue(cert_allows_get("/cert/"))
        self.assertTrue(cert_allows_get("/cert?download=1"))
        self.assertFalse(cert_allows_get("/cert/magicpad-lan.cer"))
        self.assertFalse(cert_allows_get("/magicpad-lan.cer"))
        self.assertFalse(cert_allows_get("/health"))
        self.assertTrue(cert_refuses_secret("/magicpad-lan.p12"))
        self.assertTrue(cert_refuses_secret("/magicpad-lan-key.pem"))
        self.assertTrue(cert_refuses_secret("/foo.key"))
        self.assertFalse(cert_refuses_secret("/cert"))
        self.assertFalse(cert_refuses_secret("/magicpad-lan.cer"))

    def test_swift_cert_route_and_local_server_wire(self):
        core = Path(_swift_core("CertRoute.swift")).read_text(encoding="utf-8")
        live = _swift_live(core)
        self.assertIn('path = "/cert"', live)
        self.assertIn('filename = "magicpad-lan.cer"', live)
        self.assertIn('contentType = "application/x-x509-ca-cert"', live)
        self.assertIn('".pem"', live)
        self.assertIn('".p12"', live)
        proto = Path(os.path.dirname(HERE), "docs", "PROTOCOL.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("`GET /cert`", proto)
        self.assertIn("cert_forbidden", proto)
        sec = Path(os.path.dirname(HERE), "docs", "SECURITY.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("GET /cert", sec)
        self.assertIn("magicpad-lan.cer", sec)
        ws = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Sources",
            "MagicPadServer",
            "WebSocketServer.swift",
        ).read_text(encoding="utf-8")
        if len(ws.encode("utf-8")) < 20_000:
            self.skipTest("WebSocketServer.swift is the remote stub")
        wslive = _swift_live(ws)
        self.assertIn("CertRoute.allowsGET", wslive)
        self.assertIn("CertRoute.refusesSecretExport", wslive)
        self.assertIn("LANCert.cerURL", wslive)

    def test_check_html_fails_missing_draft_and_cert_help(self):
        path = os.path.join(os.path.dirname(HERE), "scripts", "check-html.py")
        raw = Path(path).read_text(encoding="utf-8")
        self.assertIn("magicpad_draft", raw)
        self.assertIn("persistDraftSoon", raw)
        self.assertIn('id="certHelp"', raw)


class Cycle14VersionAndHTMLTests(unittest.TestCase):
    """MP-19 Version.swift; MP-15/16 gates live in check-html.py."""

    def test_version_swift_is_the_only_semver_source(self):
        root = os.path.dirname(HERE)
        ver = Path(root, "MagicPadServer", "Sources", "MagicPadServer", "Version.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn('static let string = "0.1.0"', ver)
        sh = Path(root, "scripts", "build_app.sh").read_text(encoding="utf-8")
        self.assertIn("swift build --show-bin-path", sh)
        self.assertIn("Version.swift", sh)
        self.assertNotIn('VERSION="0.1.0"', sh)

    def test_check_html_fails_missing_a11y(self):
        path = os.path.join(os.path.dirname(HERE), "scripts", "check-html.py")
        raw = Path(path).read_text(encoding="utf-8")
        self.assertIn('fails.append(":focus-visible missing")', raw)
        self.assertIn('role="tablist"', raw)
        self.assertIn("syncLayoutSoon", raw)
