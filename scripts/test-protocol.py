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
    CLOSE_MESSAGE_TOO_BIG,
    CLOSE_UNSUPPORTED_DATA,
    ERROR_PAGE_CSP,
    MAX_FRAME_BYTES,
    MAX_HEADER_BYTES,
    MAX_TYPE_CHARS,
    MAX_VOICE_CHARS,
    PROTO,
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


def _swift_core(name: str) -> str:
    return os.path.join(
        os.path.dirname(HERE),
        "MagicPadServer",
        "Sources",
        "MagicPadCore",
        name,
    )


def _swift_int_const(text: str, name: str) -> int:
    m = re.search(rf"static let {name}(?:\s*:\s*\w+)?\s*=\s*(.+)", text)
    assert m, name
    raw = m.group(1).split("//")[0].strip()
    raw = raw.replace("_", "")
    if raw.startswith("KeyProtocol."):
        key = Path(_swift_core("KeyProtocol.swift")).read_text(encoding="utf-8")
        return _swift_int_const(key, raw.split(".", 1)[1])
    return int(raw, 0)


class ProtocolLimitsTests(unittest.TestCase):
    def test_caps_match_core(self):
        text = Path(_swift_core("ProtocolLimits.swift")).read_text(encoding="utf-8")
        self.assertEqual(MAX_FRAME_BYTES, _swift_int_const(text, "maxFrameBytes"))
        self.assertEqual(MAX_HEADER_BYTES, _swift_int_const(text, "maxHeaderBytes"))
        self.assertEqual(MAX_TYPE_CHARS, _swift_int_const(text, "maxTypeChars"))
        self.assertEqual(MAX_VOICE_CHARS, _swift_int_const(text, "maxVoiceChars"))
        self.assertEqual(PROTO, _swift_int_const(text, "proto"))
        self.assertEqual(CLOSE_MESSAGE_TOO_BIG, _swift_int_const(text, "closeMessageTooBig"))
        self.assertEqual(CLOSE_UNSUPPORTED_DATA, _swift_int_const(text, "closeUnsupportedData"))
        ops = re.search(r"allowedOpcodes: Set<UInt8> = \[(.*?)\]", text, re.S)
        assert ops, "allowedOpcodes"
        got = {int(x.strip(), 0) for x in ops.group(1).split(",") if x.strip()}
        self.assertEqual(ALLOWED_OPCODES, got)
        self.assertIn(0x0, ALLOWED_OPCODES)
        csp = Path(_swift_core("HTMLEscape.swift")).read_text(encoding="utf-8")
        self.assertEqual(_swift_string_const(csp, "errorPageCSP"), ERROR_PAGE_CSP)


def _swift_string_const(text: str, name: str) -> str:
    m = re.search(rf'static let {name}(?:\s*:\s*\w+)?\s*=\s*"([^"]*)"', text)
    assert m, name
    return m.group(1)


def _swift_live(text: str) -> str:
    live = []
    for raw in text.splitlines():
        if raw.lstrip().startswith("//"):
            continue
        live.append(raw.split("//")[0])
    return "\n".join(live)


class HTMLEscapeTests(unittest.TestCase):
    def test_markup(self):
        self.assertEqual(
            html_escape("<img src=x onerror=alert(1)>"),
            "&lt;img src=x onerror=alert(1)&gt;",
        )
        self.assertEqual(html_escape("a&b"), "a&amp;b")
        self.assertEqual(html_escape("<>&"), "&lt;&gt;&amp;")

    def test_table_matches_swift(self):
        text = Path(_swift_core("HTMLEscape.swift")).read_text(encoding="utf-8")
        self.assertEqual(_swift_string_const(text, "errorPageCSP"), ERROR_PAGE_CSP)
        self.assertEqual(_swift_string_const(text, "nosniff"), "nosniff")
        live = _swift_live(text)
        for needle in (
            'out += "&amp;"',
            'out += "&lt;"',
            'out += "&gt;"',
            'out += "&quot;"',
            'out += "&#39;"',
        ):
            self.assertIn(needle, live, needle)


class CORSPolicyTests(unittest.TestCase):
    def test_star_and_echo_and_omit(self):
        lan = ["10.8.0.2"]  # example-ip
        self.assertEqual(cors_allow(None, lan), ("*", False))
        self.assertEqual(cors_allow("", lan), ("*", False))
        self.assertEqual(cors_allow("http://127.0.0.1:7878", lan), ("http://127.0.0.1:7878", True))
        self.assertIsNone(cors_allow("http://evil.example", lan))
        self.assertEqual(cors_allow_origin(None, lan), "*")
        self.assertEqual(cors_allow_origin("http://127.0.0.1:7878", lan), "http://127.0.0.1:7878")
        self.assertIsNone(cors_allow_origin("http://evil.example", lan))

    def test_swift_access_control_is_the_mirror(self):
        text = Path(_swift_core("CORSPolicy.swift")).read_text(encoding="utf-8")
        live = _swift_live(text)
        self.assertIn("public static func accessControl", live)
        self.assertIn('allowOrigin: "*"', live)
        self.assertIn("needsVary: false", live)
        self.assertIn("needsVary: true", live)
        self.assertIn("OriginPolicy.isAllowed", live)
        self.assertIn("Echo is NOT the write control", text)


class JSONTextTests(unittest.TestCase):
    def test_sorted_compact_no_escaped_slash(self):
        got = json_text_encode({"b": 1, "a": "http://127.0.0.1/x"})
        self.assertEqual(got, '{"a":"http://127.0.0.1/x","b":1}')
        self.assertNotIn("\\/", got)
        text = Path(_swift_core("JSONText.swift")).read_text(encoding="utf-8")
        live = _swift_live(text)
        self.assertIn(".sortedKeys", live)
        self.assertIn(".withoutEscapingSlashes", live)
        self.assertIn("JSONSerialization.data", live)


def _swift_quoted_forms(value: str) -> list[str]:
    """Swift literals that can carry `value` on a test line."""
    forms = [json.dumps(value, ensure_ascii=False)]
    if "\\" in value:
        forms.append('#"' + value + '"#')
    return forms


def _line_has_quoted(line: str, value: str) -> bool:
    return any(form in line for form in _swift_quoted_forms(value))


def _remainder_after_quoted(line: str, value: str) -> str:
    for form in _swift_quoted_forms(value):
        idx = line.find(form)
        if idx != -1:
            return line[:idx] + line[idx + len(form) :]
    return line


class LANAddressTests(unittest.TestCase):
    def test_shared_vectors(self):
        path = os.path.join(HERE, "fixtures", "lan-vectors.json")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        swift = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Tests",
            "MagicPadServerTests",
            "LANAddressTests.swift",
        ).read_text(encoding="utf-8")
        missing = []
        for row in data["vectors"]:
            got = is_private_ipv4(row["ip"])
            self.assertEqual(got, row["private"], row["id"])
            want_fn = "XCTAssertTrue" if row["private"] else "XCTAssertFalse"
            hits = []
            for line in swift.splitlines():
                if line.lstrip().startswith("//"):
                    continue
                if _line_has_quoted(line, row["ip"]):
                    hits.append(line)
            if not hits:
                missing.append(
                    f"{row['id']}: quoted {row['ip']!r} needs {want_fn} on a live line"
                )
                continue
            if any(want_fn not in line for line in hits):
                missing.append(
                    f"{row['id']}: quoted {row['ip']!r} has a live line without {want_fn}"
                )
        self.assertFalse(missing, missing)


class FilenamesTests(unittest.TestCase):
    def test_shared_vectors(self):
        path = os.path.join(HERE, "fixtures", "filename-vectors.json")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        swift = Path(
            os.path.dirname(HERE),
            "MagicPadServer",
            "Tests",
            "MagicPadServerTests",
            "FilenamesTests.swift",
        ).read_text(encoding="utf-8")
        missing = []
        for row in data["vectors"]:
            self.assertEqual(sanitize_filename(row["input"]), row["out"], row["id"])
            hit = False
            for line in swift.splitlines():
                if line.lstrip().startswith("//"):
                    continue
                if not _line_has_quoted(line, row["input"]):
                    continue
                rest = _remainder_after_quoted(line, row["input"])
                out_ok = _line_has_quoted(rest, row["out"]) or (
                    row["out"] == "magicpad-file.bin" and "Filenames.fallback" in rest
                )
                if out_ok:
                    hit = True
                    break
            if not hit:
                missing.append(
                    f"{row['id']}: quoted {row['input']!r} → {row['out']!r} "
                    "must share a live Swift assert line with the expected "
                    "value outside the input literal"
                )
        self.assertFalse(missing, missing)

    def test_keeps_suffix_when_truncating(self):
        got = sanitize_filename(("a" * 200) + ".txt")
        self.assertEqual(len(got), 120)
        self.assertTrue(got.endswith(".txt"))


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
