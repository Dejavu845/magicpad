#!/usr/bin/env python3
"""Static gates for MagicPadClient/index.html (stdlib; node --check if present)."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile

REV_RE = re.compile(r"MAGICPAD_HTML_REV\s*=\s*'(\d{8}-\d{4}-h\d+)'")
REV_FMT = re.compile(r"^\d{8}-\d{4}-h\d+$")
RFC1918 = re.compile(
    r"\b(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)\b"
)
FORBIDDEN_CI = re.compile(r"问 AI|ask AI|Grok|Claude|OpenAI|ChatGPT", re.I)
FORBIDDEN_CURSOR = re.compile(r"\bCursor\b")  # brand; do not match CSS cursor:
LAYOUT_TOKENS = (
    "layout-phone-port",
    "phone-land",
    "tablet-port",
    "tablet-land",
)


def strip_comments(html: str) -> str:
    html = re.sub(r"<!--.*?-->", "", html, flags=re.S)

    def js(m: re.Match[str]) -> str:
        src = m.group(1)
        out: list[str] = []
        i = 0
        n = len(src)
        while i < n:
            if src.startswith("//", i):
                nl = src.find("\n", i)
                if nl < 0:
                    break
                out.append("\n")
                i = nl + 1
                continue
            if src.startswith("/*", i):
                end = src.find("*/", i + 2)
                if end < 0:
                    break
                out.append("\n" * src[i : end + 2].count("\n"))
                i = end + 2
                continue
            out.append(src[i])
            i += 1
        return "<script>" + "".join(out) + "</script>"

    return re.sub(r"<script>(.*?)</script>", js, html, flags=re.S | re.I)


def button_ok(tag: str, inner: str) -> bool:
    low = tag.lower()
    if 'aria-hidden="true"' in low or "aria-hidden='true'" in low:
        return True
    if re.search(r"aria-label\s*=\s*['\"][^'\"]+['\"]", tag, re.I):
        return True
    text = re.sub(r"<[^>]+>", "", inner).strip()
    return bool(text)


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "MagicPadClient/index.html"
    if not os.path.isfile(path):
        print(f"FAIL missing {path}", file=sys.stderr)
        return 1
    raw = open(path, encoding="utf-8").read()
    size = len(raw.encode("utf-8"))
    fails: list[str] = []
    warns: list[str] = []

    revs = REV_RE.findall(raw)
    if len(revs) != 1:
        fails.append(f"MAGICPAD_HTML_REV count={len(revs)} (want 1)")
        rev = revs[0] if revs else ""
    else:
        rev = revs[0]
        if not REV_FMT.match(rev):
            fails.append(f"MAGICPAD_HTML_REV format {rev!r}")

    if re.search(r"<script[^>]+src\s*=", raw, re.I):
        fails.append("external <script src=")
    if re.search(r'<link[^>]+href\s*=\s*"http', raw, re.I):
        fails.append('external <link href="http')
    if re.search(r"url\(\s*['\"]?http", raw, re.I):
        fails.append("css url(http")
    if re.search(r"@import\b", raw, re.I):
        fails.append("@import")

    if not re.search(r"<html[^>]*\blang\s*=", raw, re.I):
        fails.append("missing <html lang=")
    if not re.search(r'<meta[^>]+name\s*=\s*"viewport"', raw, re.I):
        fails.append("missing viewport meta")
    if "viewport-fit=cover" not in raw:
        fails.append("missing viewport-fit=cover")

    aria_live = len(re.findall(r"aria-live", raw, re.I))
    if aria_live < 1:
        fails.append("no aria-live")
    if not re.search(r'<label[^>]+for\s*=\s*"voiceInput"', raw, re.I):
        fails.append('missing <label for="voiceInput">')

    buttons = list(re.finditer(r"<button\b([^>]*)>(.*?)</button>", raw, re.S | re.I))
    bad_btn = 0
    for m in buttons:
        if not button_ok(m.group(1), m.group(2)):
            bad_btn += 1
    if bad_btn:
        fails.append(f"{bad_btn} <button> without text or aria-label")

    if RFC1918.search(raw) and "example-ip" not in raw[max(0, RFC1918.search(raw).start() - 80) : RFC1918.search(raw).end() + 80]:
        # line-level: allow example-ip on the same line
        for i, line in enumerate(raw.splitlines(), 1):
            if RFC1918.search(line) and "example-ip" not in line:
                fails.append(f"RFC1918 literal at line {i}")
                break
    if "/Users/" in raw:
        fails.append("/Users/ path in client HTML")

    visible = strip_comments(raw)
    if FORBIDDEN_CI.search(visible) or FORBIDDEN_CURSOR.search(visible):
        for i, line in enumerate(visible.splitlines(), 1):
            if FORBIDDEN_CI.search(line) or FORBIDDEN_CURSOR.search(line):
                fails.append(f"forbidden product string at stripped line {i}: {line.strip()[:80]}")
                break

    if size > 600 * 1024:
        warns.append(f"size {size} > 600KB")

    missing_layout = [t for t in LAYOUT_TOKENS if t not in raw]
    if missing_layout:
        fails.append("missing layout tokens: " + ",".join(missing_layout))

    # WARN until MP-15
    h1_out = re.findall(r"<h1\b", re.sub(r"<noscript>.*?</noscript>", "", raw, flags=re.S | re.I), re.I)
    if len(h1_out) != 1:
        warns.append(f"heading-count <h1> outside noscript = {len(h1_out)} (want 1 after MP-15)")
    if ":focus-visible" not in raw:
        warns.append(":focus-visible missing (WARN until MP-15)")

    node_ok = "skip"
    scripts = re.findall(r"<script>(.*?)</script>", raw, re.S | re.I)
    if shutil.which("node") and scripts:
        js = "\n".join(scripts)
        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(prefix="magicpad-inline-", suffix=".js")
            os.write(fd, js.encode("utf-8"))
            os.close(fd)
            r = subprocess.run(["node", "--check", tmp], capture_output=True, text=True)
            if r.returncode != 0:
                fails.append("node --check failed: " + (r.stderr or r.stdout)[:240])
                node_ok = "fail"
            else:
                node_ok = "ok"
        finally:
            if tmp:
                try:
                    os.remove(tmp)
                except OSError:
                    pass
    elif not shutil.which("node"):
        node_ok = "skip"

    a11y = "ok" if aria_live and bad_btn == 0 else "fail"
    print(
        f"rev={rev or '?'} size={size} buttons={len(buttons)} a11y={a11y} node={node_ok}"
    )
    for w in warns:
        print(f"WARN {w}")
    if fails:
        for f in fails:
            print(f"FAIL {f}", file=sys.stderr)
        print("FAIL")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
