#!/usr/bin/env bash
# lint-repo.sh — Linux-safe static gates (syntax, forbidden files, baked IPs, product strings, integrity floors)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { echo "PASS $1"; }
skip() { echo "SKIP $1"; }
fail_step() { echo "FAIL $1"; FAIL=1; }

# --- 1. bash -n ---
if bash -n scripts/*.sh; then
  pass "bash -n scripts/*.sh"
else
  fail_step "bash -n scripts/*.sh"
fi

# --- 2. shellcheck (optional) ---
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning scripts/*.sh; then
    pass "shellcheck -S warning scripts/*.sh"
  else
    fail_step "shellcheck -S warning scripts/*.sh"
  fi
else
  skip "shellcheck (not installed)"
fi

# --- 3. py_compile ---
if python3 -m py_compile scripts/*.py; then
  rm -rf scripts/__pycache__ scripts/*.pyc
  pass "python3 -m py_compile scripts/*.py"
else
  rm -rf scripts/__pycache__ scripts/*.pyc
  fail_step "python3 -m py_compile scripts/*.py"
fi

# --- 4. QR / baked-IP invariants (print-only; no PNG) ---
if python3 scripts/generate_qr.py --print-only --http >/dev/null; then
  pass "generate_qr.py --print-only --http"
else
  fail_step "generate_qr.py --print-only --http"
fi

# --- 4b. Cycle 21/23 locks (small files; do not grow test-protocol.py) ---
if python3 -m unittest scripts/test_cycle21_qr.py scripts/test_cycle23_stt.py scripts/test_cycle24_stt_lang.py scripts/test_cycle25_stt_ondevice.py scripts/test_cycle26_binary.py scripts/test_cycle27_wstype.py scripts/test_cycle28_lan.py scripts/test_cycle29_health_pair.py -q; then
  pass "unittest cycle 21/23/24/25/26/27/28/29 small files"
else
  fail_step "unittest cycle 21/23/24/25 small files"
fi

# --- 5. tracked forbidden files ---
if git ls-files | grep -E '\.(mlmodelc|mlpackage|safetensors|p12|pem|key|cer)$|(^|/)weight\.bin$|^vendor/whisper/' >/dev/null 2>&1; then
  echo "tracked forbidden paths:" >&2
  git ls-files | grep -E '\.(mlmodelc|mlpackage|safetensors|p12|pem|key|cer)$|(^|/)weight\.bin$|^vendor/whisper/' >&2 || true
  fail_step "forbidden tracked files (weights/certs/vendor/whisper)"
else
  pass "no forbidden tracked files"
fi

# --- 6–7. RFC1918 / home-path literals + product strings (comments stripped for 7) ---
set +e
python3 - <<'PY'
import os, re, sys

root = os.getcwd()
fail = False

# Allow a line if it documents a fake address (marker required).
EXAMPLE_MARK = "example-ip"
RFC1918 = re.compile(
    r"\b(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)\b"
)
USERS = re.compile(r"/Users/[A-Za-z][A-Za-z0-9._-]*")
EXT = (".swift", ".html", ".py", ".sh", ".md", ".json")
SKIP_DIRS = {".git", "build", ".build", "node_modules", "vendor", "__pycache__"}

rfc_hits = []
user_hits = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
    for name in filenames:
        if not name.endswith(EXT):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if EXAMPLE_MARK in line:
                continue
            # generate_qr.py CLI sample uses a fake private IP; runtime QR uses LANDetector.
            if rel.replace("\\", "/").endswith("scripts/generate_qr.py"):
                continue
            if RFC1918.search(line):
                rfc_hits.append(f"{rel}:{i}:{line.strip()[:160]}")
            if USERS.search(line):
                # docs/ may mention /Users/<name> only with example-path on the line
                if ("example-path" in line) or ("example-ip" in line):
                    continue
                user_hits.append(f"{rel}:{i}:{line.strip()[:160]}")

if rfc_hits:
    print("RFC1918 literals (add example-ip on the line to allow):", file=sys.stderr)
    for h in rfc_hits:
        print("  " + h, file=sys.stderr)
    fail = True
if user_hits:
    print("/Users/<name> literals outside docs/:", file=sys.stderr)
    for h in user_hits:
        print("  " + h, file=sys.stderr)
    fail = True

if fail:
    print("LINT_RFC_FAIL")
    sys.exit(1)
print("LINT_RFC_OK")
PY
RFC_RC=$?
if [[ "$RFC_RC" -eq 0 ]]; then
  pass "no baked RFC1918 / home-path literals"
else
  fail_step "baked RFC1918 or /Users/<name> literals"
fi

python3 - <<'PY'
"""Forbidden product strings in the phone page + Swift sources (comments stripped)."""
import os, re, sys

root = os.getcwd()
pat = re.compile(r"问 AI|ask AI|\bGrok\b|\bClaude\b|\bChatGPT\b|\bOpenAI\b", re.I)

def strip_comments_swift(src: str) -> str:
    out = []
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
            chunk = src[i : end + 2]
            out.append("\n" * chunk.count("\n"))
            i = end + 2
            continue
        out.append(src[i])
        i += 1
    return "".join(out)

def strip_comments_html(src: str) -> str:
    src = re.sub(r"<!--.*?-->", "", src, flags=re.S)
    def strip_js(m):
        return "<script>" + strip_comments_swift(m.group(1)) + "</script>"
    return re.sub(r"<script>(.*?)</script>", strip_js, src, flags=re.S | re.I)

hits = []
html = os.path.join(root, "MagicPadClient/index.html")
if os.path.isfile(html):
    text = strip_comments_html(open(html, encoding="utf-8").read())
    for i, line in enumerate(text.splitlines(), 1):
        if pat.search(line):
            hits.append(f"MagicPadClient/index.html:{i}:{line.strip()[:160]}")

src_root = os.path.join(root, "MagicPadServer/Sources")
for dirpath, _, filenames in os.walk(src_root):
    for name in filenames:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        text = strip_comments_swift(open(path, encoding="utf-8").read())
        for i, line in enumerate(text.splitlines(), 1):
            if pat.search(line):
                hits.append(f"{rel}:{i}:{line.strip()[:160]}")

if hits:
    print("forbidden product strings (ask AI / cloud brands) in client or server sources:", file=sys.stderr)
    for h in hits:
        print("  " + h, file=sys.stderr)
    print("LINT_PRODUCT_FAIL")
    sys.exit(1)
print("LINT_PRODUCT_OK")
PY
PROD_RC=$?
if [[ "$PROD_RC" -eq 0 ]]; then
  pass "no forbidden product strings in client/server sources"
else
  fail_step "forbidden product strings in client/server sources"
fi

# --- 8. repo integrity (min bytes/lines; no MCP "Placeholder replaced by" stubs) ---
# Floors: WebSocketServer.swift >=20kB/500 lines, index.html >=100kB,
# smoke-all.sh >=20kB/500 lines, KeyProtocol.swift >=5kB.
# Negative proof: python3 scripts/repo_integrity.py --prove-stub  (temp 140-byte stub must FAIL)
if python3 scripts/repo_integrity.py; then
  pass "repo integrity floors"
else
  fail_step "repo integrity floors"
fi
if python3 scripts/repo_integrity.py --prove-stub; then
  pass "repo integrity stub probe (140-byte WebSocketServer would FAIL)"
else
  fail_step "repo integrity stub probe"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "lint-repo FAIL"
  exit 1
fi
echo "lint-repo PASS"
exit 0
