#!/usr/bin/env python3
"""Repo file-integrity floors so a 140-byte MCP stub cannot pass linux-checks.

Cycle 1's remote branch replaced WebSocketServer.swift with a one-line
placeholder; CI still reported success because no gate looked at size.
This module is imported by scripts/lint-repo.sh and scripts/test-protocol.py.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile

# Exact remote stub on origin/cursor/eng-loop-895b (140 bytes, em-dash UTF-8).
REMOTE_WS_STUB = (
    b"// WebSocketServer.swift \xe2\x80\x94 local tree sync (see MagicPadServer). "
    b"Placeholder replaced by full file in this commit if content is complete.\n"
)
PLACEHOLDER_MARK = "Placeholder replaced by"

# (relpath, min_bytes, min_lines or None)
CRITICAL_FLOORS: tuple[tuple[str, int, int | None], ...] = (
    ("MagicPadServer/Sources/MagicPadServer/WebSocketServer.swift", 20_000, 500),
    ("MagicPadClient/index.html", 100_000, None),
    ("scripts/smoke-all.sh", 20_000, 500),
    ("MagicPadServer/Sources/MagicPadCore/KeyProtocol.swift", 5_000, None),
)

SOURCES_MIN_BYTES = 200


def iter_source_swift(root: str):
    src = os.path.join(root, "MagicPadServer", "Sources")
    if not os.path.isdir(src):
        return
    for dirpath, _, filenames in os.walk(src):
        for name in filenames:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def line_count(raw: bytes) -> int:
    text = raw.decode("utf-8", "replace")
    if not text:
        return 0
    return len(text.splitlines())


def check(root: str) -> list[str]:
    """Return human-readable issues; empty list means the tree passes."""
    issues: list[str] = []
    for rel, min_bytes, min_lines in CRITICAL_FLOORS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            issues.append(f"missing {rel}")
            continue
        with open(path, "rb") as f:
            raw = f.read()
        n = len(raw)
        if n < min_bytes:
            issues.append(f"{rel} is {n} bytes; need >= {min_bytes}")
        if min_lines is not None:
            nlines = line_count(raw)
            if nlines < min_lines:
                issues.append(f"{rel} is {nlines} lines; need >= {min_lines}")

    for path in iter_source_swift(root):
        rel = os.path.relpath(path, root).replace("\\", "/")
        with open(path, "rb") as f:
            raw = f.read()
        text = raw.decode("utf-8", "replace")
        if PLACEHOLDER_MARK in text:
            issues.append(f"{rel} contains {PLACEHOLDER_MARK!r}")
        if len(raw) < SOURCES_MIN_BYTES:
            issues.append(
                f"{rel} is {len(raw)} bytes; Sources/**/*.swift need >= {SOURCES_MIN_BYTES}"
            )
    return issues


def materialize_probe_tree(live_root: str, dest: str) -> None:
    """Copy the critical files + Sources so a stub overwrite is realistic."""
    src_src = os.path.join(live_root, "MagicPadServer", "Sources")
    dst_src = os.path.join(dest, "MagicPadServer", "Sources")
    shutil.copytree(src_src, dst_src)
    html_src = os.path.join(live_root, "MagicPadClient", "index.html")
    html_dst = os.path.join(dest, "MagicPadClient", "index.html")
    os.makedirs(os.path.dirname(html_dst), exist_ok=True)
    shutil.copy2(html_src, html_dst)
    smoke_src = os.path.join(live_root, "scripts", "smoke-all.sh")
    smoke_dst = os.path.join(dest, "scripts", "smoke-all.sh")
    os.makedirs(os.path.dirname(smoke_dst), exist_ok=True)
    shutil.copy2(smoke_src, smoke_dst)


def stub_issues(live_root: str) -> list[str]:
    """Clone live_root, overwrite WebSocketServer.swift with today's 140-byte stub."""
    if len(REMOTE_WS_STUB) != 140:
        raise AssertionError(f"REMOTE_WS_STUB is {len(REMOTE_WS_STUB)} bytes, want 140")
    with tempfile.TemporaryDirectory(prefix="magicpad-integrity-") as td:
        materialize_probe_tree(live_root, td)
        rel = "MagicPadServer/Sources/MagicPadServer/WebSocketServer.swift"
        dest = os.path.join(td, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(REMOTE_WS_STUB)
        return check(td)


def prove_stub(live_root: str) -> int:
    """Exit 0 if today's 140-byte stub would fail the gate (the proof succeeded)."""
    issues = stub_issues(live_root)
    size_hit = any("WebSocketServer.swift" in i and "bytes" in i for i in issues)
    mark_hit = any(PLACEHOLDER_MARK in i for i in issues)
    if not (size_hit and mark_hit):
        print("PROVE_STUB FAIL: 140-byte stub did not trip size floor AND placeholder", file=sys.stderr)
        for i in issues:
            print("  " + i, file=sys.stderr)
        return 1
    print("PROVE_STUB OK: 140-byte WebSocketServer stub rejected")
    for i in issues:
        if "WebSocketServer" in i or PLACEHOLDER_MARK in i:
            print("  " + i)
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="MagicPad repo integrity floors")
    p.add_argument("--root", default=os.getcwd(), help="Repo root (default: cwd)")
    p.add_argument(
        "--prove-stub",
        action="store_true",
        help="Dry-run: overwrite a temp clone's WebSocketServer.swift with the "
        "140-byte remote stub and require the gate to fail (exit 0 = proof ok)",
    )
    args = p.parse_args(argv)
    root = os.path.abspath(args.root)
    if args.prove_stub:
        return prove_stub(root)
    issues = check(root)
    if issues:
        print("repo integrity FAIL:", file=sys.stderr)
        for i in issues:
            print("  " + i, file=sys.stderr)
        return 1
    print("repo integrity OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
