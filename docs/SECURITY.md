# MagicPad security (LAN injector)

Unauthenticated mouse/keyboard/clipboard injection on the **same Wi‑Fi** is the product. There is no login and no public URL. See `docs/ENGINEERING.md` for the full threat table (MP-12 expands this).

## Cross-site WebSocket hijack (CSWSH)

Any page a LAN browser has open can run `new WebSocket('ws://<mac-ip>:7878')`. Without an Origin check that is arbitrary CGEvent injection.

**Control (MP-01) — WebSocket handshake only.** `OriginPolicy.isAllowed` in `MagicPadCore`. Handshake in `WSConnection.handleHandshake`:

- Missing `Origin` header (`nil`) → allow (curl and `scripts/smoke-ws.py` default).
- Empty `Origin` *value* in `OriginPolicy` (`trimmed.isEmpty`) → allow. **The current server parser never produces `""`.** `String.split` defaults to `omittingEmptySubsequences: true`, so a header line `Origin:` becomes the literal `"Origin"` and is **rejected** (fail-closed). Cycle 3: `HTTPHeaderValue.first` (`MagicPadCore`) returns `""` for that line — see `docs/CYCLE3-HTTP-ORIGIN.md`.
- Scheme must be `http` / `https` / `ws` / `wss`.
- Host must be `127.0.0.1`, `localhost`, `::1`, or a current private IPv4 from `LANDetector`.
- `"null"` (opaque origin) → reject.
- Reject → `HTTP/1.1 403 Forbidden` + `MagicLog.ws("handshake origin rejected host=…")` (host only, not full headers).

Debug hatch (documented, default off): `MAGICPAD_ALLOW_ANY_ORIGIN=1`. Do not leave this set.

Phone page served from the live LAN IP still connects: that IP is in `LANDetector.allPrivateIPs` plus `LANDetector.ip`. HTTPS `:7879` uses the same host list. Hostname / mDNS (`*.local`) is **not** on the allowlist — only IP-literal (and loopback) access is supported today.

**MP-01 does not close HTTP.** `POST /drop` and `POST /stt` in `beginHTTPPost` do not read `Origin`. `autoPaste` defaults to true, so a CORS-simple `fetch(..., {mode:'no-cors'})` from any origin can write the pasteboard and synthesize Cmd+V. Changing `Access-Control-Allow-Origin` (leftover MP-04 as originally written) only affects who may *read* replies; it does not stop the write. Cycle 3 adds `HTTPPostOrigin.allows` in Core but does not yet call it from `beginHTTPPost`. Until that insert (see `docs/CYCLE3-HTTP-ORIGIN.md`), do not describe CSWSH as closed on the HTTP door.

## What `/health` may expose

Service flags, ports, RFC1918 IPs currently bound, `htmlRev`, inject/gesture counters, Whisper **variant name** (tiny/base). Never hostname, home path, SSID, user, or payload text.

This no-home-path promise is **scoped to `GET /health` JSON**. HTML 404/503 bodies (`fallbackHTML`) may still interpolate the request path and, when `index.html` is missing, `StaticFileLocator.indexHTMLCandidates()` (bundle/source paths, including `/Users/<name>`). Those pages are not covered by the `/health` smoke assertions.

## Intentional fail-closed Origin rejects

Exact-set host match, no IPv4/IPv6 normalization. These are **rejected on purpose** — do not "fix" them into host canonicalization:

- IPv6 forms other than `::1` after bracket strip: `[0:0:0:0:0:0:0:1]`, `[::ffff:127.0.0.1]`, zone IDs (`fe80::1%25en0`)
- Alternate IPv4: `127.1`, `2130706433`, `0x7f.0.0.1`
- Trailing-dot `localhost.`
- mDNS / hostname (`http://mymac.local`) — unsupported until MP-22 decides otherwise

`OriginPolicy.host(fromOrigin:)` uses the same `parse` as `isAllowed` (scheme required). `file://127.0.0.1` → nil. Path / query / fragment / userinfo Origins are rejected, including present-but-empty `?` / `#` / `@`. `percentEncodedHost` plus a `%` reject closes a decode-then-compare bypass: `http://%31%32%37.0.0.1` used to decode to `127.0.0.1` and match the allowlist.

## Cycle 4 helpers (not yet on the live 62 KB server file)

`HTMLEscape.escape` + `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'` + `X-Content-Type-Options: nosniff` are the intended fix for the reflected `fallbackHTML` sink (Opus H1). A 503 that lists `index.html` candidates must use `sourceLabel()`, not filesystem paths. `CORSPolicy` only changes who may *read* replies (`needsVary` travels with the ACAO value). Insert both per `docs/CYCLE4-WIRING.md` after a human restore of `WebSocketServer.swift`.

## Reporting

GitHub issue on this repo. Do not mail secrets or LAN IPs to a personal inbox.
