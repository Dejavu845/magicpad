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

**MP-01 is WebSocket-only.** Cycle 7 also calls `HTTPPostOrigin.allows` in `beginHTTPPost` for `POST /drop` and `POST /stt` (same missing/empty Origin carve-out as the handshake). A CORS-simple `no-cors` POST from a disallowed Origin is now 403 before pasteboard/STT. CORS echo (`CORSPolicy.accessControl`) still only affects who may *read* replies. The remote draft PR's 140-byte stub does **not** include this insert until a human `git push`.

## What `/health` may expose

Service flags, ports, RFC1918 IPs currently bound, `htmlRev`, inject/gesture counters, Whisper **variant name** (tiny/base), additive `proto`. Never hostname, home path, SSID, user, or payload text. Cross-origin browsers do not read this JSON unless CORS echoes their Origin; curl without Origin still gets `*`. `ip`/`ips`/`ifaces` stay for same-LAN debug — they are not removed.

This no-home-path promise is **scoped to `GET /health` JSON**. HTML 404/503 bodies (`fallbackHTML`) may still interpolate the request path and, when `index.html` is missing, `StaticFileLocator.indexHTMLCandidates()` (bundle/source paths, including `/Users/<name>` example-path). Those pages are not covered by the `/health` smoke assertions.

A pairing token on the QR / `hello` is optional and default-off. **Never put a pairing token in `/health`.**

## Intentional fail-closed Origin rejects

Exact-set host match, no IPv4/IPv6 normalization. These are **rejected on purpose** — do not "fix" them into host canonicalization:

- IPv6 forms other than `::1` after bracket strip: `[0:0:0:0:0:0:0:1]`, `[::ffff:127.0.0.1]`, zone IDs (`fe80::1%25en0`)
- Alternate IPv4: `127.1`, `2130706433`, `0x7f.0.0.1`
- Trailing-dot `localhost.`
- mDNS / hostname (`http://mymac.local`) — unsupported until MP-22 decides otherwise

`OriginPolicy.host(fromOrigin:)` uses the same `parse` as `isAllowed` (scheme required). `file://127.0.0.1` → nil. Path / query / fragment / userinfo Origins are rejected, including present-but-empty `?` / `#` / `@`. `percentEncodedHost` plus a `%` reject closes a decode-then-compare bypass: `http://%31%32%37.0.0.1` used to decode to `127.0.0.1` and match the allowlist.

## Cycle 4 helpers (not yet on the live 62 KB server file)

`HTMLEscape.escape` + `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'` + `X-Content-Type-Options: nosniff` are the intended fix for the reflected `fallbackHTML` sink (Opus H1). A 503 that lists `index.html` candidates must use `sourceLabel()`, not filesystem paths. `CORSPolicy` only changes who may *read* replies (`needsVary` travels with the ACAO value). Insert both per `docs/CYCLE4-WIRING.md` after a human restore of `WebSocketServer.swift`.

## GET /cert (MP-22)

`GET /cert` is the only HTTP export of the LAN TLS identity. It serves `magicpad-lan.cer` (DER) with `application/x-x509-ca-cert`. It must not serve `magicpad-lan.p12`, `magicpad-lan-cert.pem`, `magicpad-lan-key.pem`, or any `.key`. Those stay on disk for `LANCert` only. A missing `.cer` is 404 `cert_not_ready`, not a fallback to PEM. Cycle 15 whitelist is `CertRoute`; local `serveStaticFile` wires it. Remote stub unrestored until a human `git push`.

## On-device STT only (MP-14)

`SpeechSession` must not call Apple Speech with `requiresOnDeviceRecognition = false`. If Whisper weights are missing and Apple on-device recognition is unsupported, the reason is `no_on_device_stt` (live `stt` and `POST /stt`). Cloud STT / LLM remain out of product scope.

## Reporting

GitHub issue on this repo. Do not mail secrets or LAN IPs to a personal inbox.
