#!/usr/bin/env python3
"""MagicPad HTTPS smoke — TLS :7879 /health contract (OPT-26).

Usage:
  python3 scripts/smoke-https.py
  HTTPS_HOST=127.0.0.1 HTTPS_PORT=7879 python3 scripts/smoke-https.py
  HTTPS_TIMEOUT=5 HTTPS_RETRIES=1 python3 scripts/smoke-https.py

PASS when curl-equivalent GET https://HOST:PORT/health returns JSON with
  https:true and port/url keys (httpsPort, httpsUrl or port).

Preflight (proxy-free) GET http://127.0.0.1:7878/health (or HTTP_HEALTH_URL):
  - HTTP down → FAIL reason=app_down (not TLS)
  - HTTP up & https:true but TLS fails → reason=tls_handshake (stage=connect|read)

Exit 0 on PASS, 1 on FAIL (caller may isolate so HTTP smoke still passes).
No third-party deps; stdlib only. Insecure TLS (self-signed) by design.
"""
from __future__ import annotations

import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request

HOST = os.environ.get("HTTPS_HOST", os.environ.get("BASE_HOST", "127.0.0.1"))
PORT = int(os.environ.get("HTTPS_PORT", "7879"))
# Default 4–6s; env override
TIMEOUT = float(os.environ.get("HTTPS_TIMEOUT", os.environ.get("SMOKE_HTTPS_TIMEOUT", "5")))
# 1–2 retries on timeout/URLError (total attempts = 1 + retries)
RETRIES = int(os.environ.get("HTTPS_RETRIES", "1"))
RETRIES = max(0, min(2, RETRIES))
HTTP_HEALTH = os.environ.get(
    "HTTP_HEALTH_URL",
    os.environ.get("BASE_URL", "http://127.0.0.1:7878").rstrip("/") + "/health",
)


def _strip_proxy_env() -> None:
    # Bypass local HTTP(S)_PROXY (Clash/etc.) — LAN self-signed must be direct
    for k in (
        "http_proxy",
        "https_proxy",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "all_proxy",
        "ALL_PROXY",
    ):
        os.environ.pop(k, None)
    os.environ.setdefault("NO_PROXY", "*")
    os.environ.setdefault("no_proxy", "*")


def _classify_url_error(err: BaseException) -> tuple[str, str]:
    """Return (stage, short_reason) for URLError / timeout / SSL.

    stage: connect | read | unknown
    """
    # urllib wraps socket.timeout and SSL errors inside URLError.reason
    reason = getattr(err, "reason", err)
    msg = str(reason if reason is not None else err).lower()
    name = type(reason).__name__ if reason is not None else type(err).__name__

    if isinstance(reason, socket.timeout) or "timed out" in msg or name == "TimeoutError":
        # Heuristic: handshake timeouts are connect-stage; partial body = read
        if "handshake" in msg or "ssl" in msg or "tls" in msg:
            return "connect", "tls_handshake_timeout"
        return "connect", "timeout"

    if isinstance(reason, ConnectionRefusedError) or "connection refused" in msg:
        return "connect", "connection_refused"

    if isinstance(reason, ssl.SSLError) or "ssl" in msg or "tls" in name.lower():
        return "connect", "tls_handshake"

    if isinstance(reason, (socket.gaierror, OSError)):
        if "errno 61" in msg or "errno 111" in msg:  # macOS/Linux ECONNREFUSED
            return "connect", "connection_refused"
        if "errno 60" in msg or "errno 110" in msg:  # ETIMEDOUT
            return "connect", "timeout"
        return "connect", "network"

    if "incomplete" in msg or "partial" in msg or "read" in msg:
        return "read", "read_error"

    return "unknown", "url_error"


def _http_preflight() -> tuple[str | None, dict | None, str]:
    """GET HTTP /health. Returns (fail_reason_or_None, health_json_or_None, detail)."""
    try:
        req = urllib.request.Request(HTTP_HEALTH, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=min(TIMEOUT, 4.0)) as r:
            raw = r.read().decode("utf-8", errors="replace")
            status = getattr(r, "status", 200)
    except Exception as e:
        stage, short = _classify_url_error(e)
        return (
            "app_down",
            None,
            f"HTTP preflight fail stage={stage} reason={short}: {e}",
        )

    if status and int(status) >= 400:
        return "app_down", None, f"HTTP preflight HTTP {status} from {HTTP_HEALTH}"

    try:
        h = json.loads(raw)
    except Exception as e:
        return "app_down", None, f"HTTP preflight non-JSON: {e} body={raw[:120]!r}"

    if not isinstance(h, dict) or not h.get("ok"):
        return "app_down", h if isinstance(h, dict) else None, "HTTP /health ok!=true"

    return None, h, "HTTP preflight ok"


def _tls_get(url: str, ctx: ssl.SSLContext) -> tuple[int, str]:
    """One TLS GET attempt. Raises on network/TLS failure."""
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
        # read stage (timeout here → read)
        raw = r.read().decode("utf-8", errors="replace")
        status = getattr(r, "status", 200)
        return int(status or 200), raw


def main() -> int:
    _strip_proxy_env()
    url = f"https://{HOST}:{PORT}/health"
    ctx = ssl._create_unverified_context()

    # --- Preflight HTTP :7878 so app_down ≠ tls_handshake ---
    app_fail, http_health, pre_detail = _http_preflight()
    if app_fail == "app_down":
        print(
            f"smoke-https FAIL reason=app_down stage=connect detail={pre_detail}",
            file=sys.stderr,
        )
        return 1
    # stdout may be fully buffered under capture — flush so stage order is correct
    print(f"smoke-https preflight: {pre_detail}", flush=True)
    if http_health is not None:
        print(
            "smoke-https preflight https=%s httpsPort=%s"
            % (http_health.get("https"), http_health.get("httpsPort")),
            flush=True,
        )

    http_claims_https = bool(http_health and http_health.get("https") is True)

    last_err: BaseException | None = None
    last_stage = "unknown"
    last_short = "unknown"
    attempts = 1 + RETRIES
    status = 0
    raw = ""

    for attempt in range(1, attempts + 1):
        try:
            status, raw = _tls_get(url, ctx)
            last_err = None
            break
        except urllib.error.HTTPError as e:
            # Got TLS + HTTP response with error code — not a handshake fail
            try:
                raw = e.read().decode("utf-8", errors="replace")
            except Exception:
                raw = ""
            status = int(e.code or 500)
            last_err = None
            break
        except urllib.error.URLError as e:
            last_err = e
            last_stage, last_short = _classify_url_error(e)
            print(
                f"smoke-https try {attempt}/{attempts} FAIL stage={last_stage} "
                f"reason={last_short}: {e}",
                file=sys.stderr,
            )
            if attempt < attempts:
                time.sleep(0.35 * attempt)
                continue
        except socket.timeout as e:
            last_err = e
            last_stage, last_short = "connect", "timeout"
            print(
                f"smoke-https try {attempt}/{attempts} FAIL stage={last_stage} "
                f"reason={last_short}: {e}",
                file=sys.stderr,
            )
            if attempt < attempts:
                time.sleep(0.35 * attempt)
                continue
        except Exception as e:
            last_err = e
            last_stage, last_short = _classify_url_error(e)
            print(
                f"smoke-https try {attempt}/{attempts} FAIL stage={last_stage} "
                f"reason={last_short}: {e}",
                file=sys.stderr,
            )
            if attempt < attempts:
                time.sleep(0.35 * attempt)
                continue

    if last_err is not None:
        # HTTP was up; classify residual TLS failure
        if http_claims_https or last_stage == "connect":
            reason = "tls_handshake"
        else:
            reason = last_short or "tls_fail"
        print(
            f"smoke-https FAIL reason={reason} stage={last_stage} "
            f"url={url} detail={last_err}",
            file=sys.stderr,
        )
        if http_claims_https:
            print(
                "smoke-https note: HTTP /health reports https:true but TLS "
                f":{PORT} failed (stage={last_stage})",
                file=sys.stderr,
            )
        return 1

    if status and int(status) >= 400:
        print(
            f"smoke-https FAIL reason=http_status stage=read HTTP {status} from {url}",
            file=sys.stderr,
        )
        return 1

    try:
        h = json.loads(raw)
    except Exception as e:
        print(
            f"smoke-https FAIL reason=bad_json stage=read: {e} body={raw[:200]!r}",
            file=sys.stderr,
        )
        return 1

    # Required: https:true + port/url keys (aligned with /health dual-port contract)
    if h.get("https") is not True:
        print(
            f"smoke-https FAIL reason=https_false stage=read: https must be true, "
            f"got {h.get('https')!r}",
            file=sys.stderr,
        )
        return 1

    # Port keys: prefer httpsPort; accept port as fallback
    has_port = isinstance(h.get("httpsPort"), (int, float)) or isinstance(
        h.get("port"), (int, float)
    )
    if not has_port:
        print(
            "smoke-https FAIL reason=missing_port stage=read: missing httpsPort/port",
            file=sys.stderr,
        )
        return 1

    # URL key optional but preferred when present must be non-empty string
    if "httpsUrl" in h and not isinstance(h.get("httpsUrl"), str):
        print(
            f"smoke-https FAIL reason=bad_httpsUrl stage=read: httpsUrl must be str, "
            f"got {type(h.get('httpsUrl')).__name__}",
            file=sys.stderr,
        )
        return 1
    if "httpsUrl" in h and h.get("https") is True and not (h.get("httpsUrl") or "").strip():
        print(
            "smoke-https FAIL reason=empty_httpsUrl stage=read: httpsUrl empty while https=true",
            file=sys.stderr,
        )
        return 1

    print(
        "smoke-https PASS https=%s httpsPort=%s httpsUrl=%r port=%s"
        % (
            h.get("https"),
            h.get("httpsPort"),
            h.get("httpsUrl"),
            h.get("port"),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
