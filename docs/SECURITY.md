# MagicPad security (LAN injector)

Unauthenticated mouse/keyboard/clipboard injection on the **same Wi‑Fi** is the product. There is no login and no public URL. See `docs/ENGINEERING.md` for the full threat table (MP-12 expands this).

## Cross-site WebSocket hijack (CSWSH)

Any page a LAN browser has open can run `new WebSocket('ws://<mac-ip>:7878')`. Without an Origin check that is arbitrary CGEvent injection.

**Control (MP-01):** `OriginPolicy.isAllowed` in `MagicPadCore`. Handshake in `WSConnection.handleHandshake`:

- Missing / empty `Origin` → allow (curl and `scripts/smoke-ws.py` default).
- Scheme must be `http` / `https` / `ws` / `wss`.
- Host must be `127.0.0.1`, `localhost`, `::1`, or a current private IPv4 from `LANDetector`.
- `"null"` (opaque origin) → reject.
- Reject → `HTTP/1.1 403 Forbidden` + `MagicLog.ws("handshake origin rejected host=…")` (host only, not full headers).

Debug hatch (documented, default off): `MAGICPAD_ALLOW_ANY_ORIGIN=1`. Do not leave this set.

Phone page served from the live LAN IP still connects: that IP is in `LANDetector.allPrivateIPs` plus `LANDetector.ip`. HTTPS `:7879` uses the same host list.

## What `/health` may expose

Service flags, ports, RFC1918 IPs currently bound, `htmlRev`, inject/gesture counters, Whisper **variant name** (tiny/base). Never hostname, home path, SSID, user, or payload text.

## Reporting

GitHub issue on this repo. Do not mail secrets or LAN IPs to a personal inbox.
