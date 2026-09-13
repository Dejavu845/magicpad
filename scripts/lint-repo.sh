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
if python3 -m unittest scripts/test_cycle21_qr.py scripts/test_cycle23_stt.py scripts/test_cycle24_stt_lang.py scripts/test_cycle25_stt_ondevice.py scripts/test_cycle26_binary.py scripts/test_cycle27_wstype.py scripts/test_cycle28_lan.py scripts/test_cycle29_health_pair.py scripts/test_cycle30_classify.py scripts/test_cycle31_lan_fixtures.py scripts/test_cycle32_classify_health.py scripts/test_cycle33_classify_http.py scripts/test_cycle34_qr_classify.py -q; then
  pass "unittest cycle 21/23/24/25/26/27/28/29/30/31/32/33/34 small files"
else
  fail_step "unittest cycle 21/23/24/25 small files"
fi

# --- 5. tracked forbidden files ---
if git ls-files | grep -E '\\.(mlmodelc|mlpackage|safetensors|p12|pem|key|cer)$|(^|/)weight\\.bin$|^vendor/whisper/' >/dev/null 2>&1; then
  echo "tracked forbidden paths:" >&2
  git ls-files | grep -E '\\.(mlmodelc|mlpackage|safetensors|p12|pem|key|cer)$|(^|/)weight\\.bin$|^vendor/whisper/' >/dev/null 2>&1; then
