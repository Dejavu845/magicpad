# MagicPad optimizations — implemented vs leftover

Ranked work from the Cycle 1 engineering pass and Cycle 2 integrity/docs. **Do not** open items for: cloud LLM/agent, public tunnel, Whisper weights in git, phone App Store app, 13B/18B layout changes, or `pending/armed/multi`.

Priority: **P0** security/correctness · **P1** gates and product-visible fixes · **P2** nice-to-have.  
Linux: **YES** fully verifiable here · **WRITE** Swift written here, Mac owner compiles.

## Implemented (Cycle 1)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-08 | P1 | YES | `.cursor/environment.json` (shellcheck + pip; Swift optional / non-fatal) |
| MP-06 | P1 | YES | `scripts/lint-repo.sh` — bash -n, shellcheck, py_compile, QR invariants, forbidden files, baked IPs, product strings |
| MP-07 | P1 | YES | `scripts/check-html.py` — rev format, no CDN, a11y baseline, node --check |
| MP-09 | P1 | YES | `scripts/magicpad_proto.py` + `scripts/test-protocol.py` + `scripts/fixtures/key-aliases.json` |
| MP-05 | P1 | YES | GitHub Actions `linux-checks` + PR template + README CI line |
| MP-10 | P1 | YES | Host validation, `escapeHtml`, HTTPS tip without string-concat `innerHTML` |
| MP-01 | P0 | WRITE | `OriginPolicy` — reject non-LAN WebSocket `Origin` (403). Hatch `MAGICPAD_ALLOW_ANY_ORIGIN=1`. **Does not cover HTTP POST.** |
| MP-03 | P0 | WRITE | `KeyProtocol.parseVoice` — clamp 20_000 graphemes, ack `voice_truncated`; Cycle 2 `bad_voice` for non-string `text` |
| MP-25 | P0 | YES | `lint-repo.sh` integrity floors + placeholder marker; `--prove-stub` rejects the 140-byte remote WebSocketServer |
| MP-26 | P1 | YES | `smoke-ws.py --expect-reject` (403 assertion reusable outside `smoke-all.sh`) |
| MP-27 | P0 | WRITE | `HTTPHeaderValue` + `HTTPPostOrigin` in Core + `docs/CYCLE3-HTTP-ORIGIN.md` (not yet called from `beginHTTPPost`) |
| MP-28 | P0 | YES | `OriginPolicy.parse`: reject path/query/fragment/userinfo/`%` host; `host(fromOrigin:)` shares parse; `scripts/fixtures/origin-vectors.json` drives the Python table; `OriginPolicyTests.swift` is hand-copied and `test-protocol.py` asserts every fixture origin string appears in that Swift file |

Minimal docs shipped with those items: `docs/SECURITY.md` (CSWSH / Origin; HTTP gap; `/health`-scoped path promise), `docs/PROTOCOL.md` (JSON catalogue seed). Full MP-12 still leftover.

## Cycle 4 — implemented (helpers only; WebSocketServer not rewritten)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-02 | P0 | WRITE | `ProtocolLimits` + Python mirror. **Not wired** into `parseFrame` / handshake (`docs/CYCLE4-WIRING.md`). |
| MP-04 echo | P0 | WRITE | `CORSPolicy.accessControl` — echo allowlist / omit / `*` plus `needsVary`. **Not the write control.** |
| H1 helper | P0 | WRITE | `HTMLEscape.escape` + CSP/nosniff constants for `fallbackHTML`. |
| MP-17 seed | P1 | WRITE | `JSONText.encode` (sorted keys). |
| MP-18 seed | P2 | WRITE | `LANAddress.isPrivate` + `Filenames.sanitize` + Python mirrors. |

## Cycle 5 — Opus C3 follow-up (docs + mirror fidelity)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-28 parity | P1 | YES | Fixture comment + `test_every_fixture_origin_appears_in_swift`; added `localhost-suffix` and four empty query/fragment/userinfo rows to the Swift table |
| MP-28 mirror | P1 | YES | Python `origin_parse` rejects raw `?`/`#` and `username is not None` so empty query/fragment/userinfo match Swift |
| MP-28 docs | P1 | YES | `SECURITY.md` present tense + decode-then-compare note; `HTTPPostOrigin.swift` states the helper is not yet called |

## Cycle 6 — Opus C4 follow-up

| ID | Pri | Linux | What landed |
|---|---|---|---|
| C4-B2/B3 | P0 | YES | `docs/CYCLE4-WIRING.md`: do not `closeInternal` under `parseFrame`'s lock; add `sendCloseFrame(code:)`; `0x0` listed, reassembly not in the insert |
| C4-H2 | P0 | YES | 503 must use `sourceLabel()`, not `indexHTMLCandidates()` paths (home-path rule) |
| C4-H3 | P1 | YES | `test-protocol.py` reads `ProtocolLimits.swift` / `HTMLEscape.swift`; `lan-vectors.json` + `filename-vectors.json` |
| C4-M1/M3 | P1 | WRITE | `LANAddress` / Python require four octets and `0...255`; `LANDetector.isPrivate` delegates |
| C4-M2/N2 | P1 | WRITE | Unicode filenames; `\` is a separator; truncate keeps suffix; `FileDropPasteboard` calls `Filenames.sanitize` |
| C4-M4/M6 | P1 | WRITE | `ProtocolLimits` type/voice caps read `KeyProtocol`; header says 1 MiB / 16 KiB are new |
| C4-M5/M7/M8 | P1 | YES | PROTOCOL opcode/version caveats; CORS `needsVary`; CSP `style-src 'unsafe-inline'` |

## Cycle 7 — wired on the local 62 KB server (remote stub unrestored)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-02 wire | P0 | WRITE | `parseFrame` sets `pendingCloseCode` and returns; close + `sendCloseFrame(code:)` after unlock. Header 431. Version 426. `0x0` allowed, no reassembly. |
| MP-04 write | P0 | WRITE | `HTTPPostOrigin.allows` in `beginHTTPPost` before pasteboard/STT. Handshake Origin/key use `HTTPHeaderValue.first`. |
| C4-H2 wire | P0 | WRITE | 503 lists `sourceLabel()`, not filesystem paths. `fallbackHTML` uses `HTMLEscape.escape`. |
| MP-04 echo | P0 | WRITE | `CORSPolicy.accessControl` on HTTP replies (`*` when Origin missing). |
| C6-B1 | P0 | WRITE | `import MagicPadCore` on `LANDetector` / `FileDropPasteboard` (Swift file-scoped imports). |
| C6-M1 | P0 | YES | Wiring doc: handle `pendingCloseCode` **after** the `while let parseFrame` loop. |
| C6-M2 | P1 | YES | Fixture rows must share a live Swift assert line with the expected True/False or output. |
| C6-M3 | P1 | YES | Python `is_private_ipv4` rejects non-ASCII / non-digit octets (`int("1_0")` ≠ Swift `Int`). |
| C6-M4 | P1 | YES | NFC before the filename filter (APFS NFD `é`). Fixture `nfd-e-acute`. |

## Cycle 8 — Opus C7 follow-up (local 62 KB server; remote stub unrestored)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| C7-M1 | P0 | WRITE | 64-bit length `v > Int.max` sets `pendingCloseCode` (1009) before `return nil`. |
| C7-M2 | P0 | WRITE | `beginHTTPPost` uses `HTTPHeaderValue.first`; `headerValue` deleted. |
| C7-M3 | P1 | YES | Core file headers no longer say the Cycle 7 wires are unwired. |
| C7-M4 | P1 | YES | Fixture gate anchors on quoted literals; expected value must sit outside the input literal. |
| C7-M5 | P1 | YES | `smoke-all.sh` POST /drop Origin evil → 403 `origin_rejected`; loopback → 200. Grep-locked. |
| C7-M6 | P1 | WRITE | Both languages require 1–3 ASCII digits (reject `+` / `_` / Arabic-Indic / 4-digit octets). |

## Cycle 9 — Opus C7 nits (local server; remote stub unrestored)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| C7-N1 | P1 | WRITE | 403/426 handshake return `.closing`; caller does not `closeInternal()` until send completes. |
| C7-N2 | P1 | WRITE | One `range(of: CRLFCRLF)` scan; dead `guard` removed. |
| C7-N3 | P1 | WRITE | `sentHeaderTooLarge` so a second receive does not send a second 431. |
| C7-N4 | P1 | WRITE | 503 candidate labels are `Set` + `sorted` (no `bundle · bundle`). |
| C7-N5/N6 | P1 | YES | HTMLEscape / CORS tests open the Swift files; CSP is the `static let` value, not a file substring. |
| C7-N9 | P1 | WRITE | Comment: pre-handshake `buffer` is the NWConnection receive queue; `parseFrame` takes `lock`. |

## Cycle 10 — MP-11 / MP-17 / C7 N8 (local server; remote stub unrestored)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-11 | P1 | WRITE | `proto: 1` on local `hello` / `hello_ack` / `/health`. |
| MP-17 | P1 | WRITE | `/health` and `hello_ack` use `JSONText.encode`. |
| C7-N8 | P1 | YES | `JSONText` uses `.withoutEscapingSlashes`. docs `/Users/` lines need `example-path`. |

## Cycle 11 — MP-13 log redact (local server; EventInjector unrestored on remote)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-13 | P1 | WRITE | No `text.prefix` in type/voice logs. `/tmp/magicpad-server.log` is `0600`. |
| MP-12 | P1 | YES | PROTOCOL lists the `/health` key set. |

Remote PR still has the 140-byte stub. Human `git push` required. Do not MCP-upload `WebSocketServer.swift`, `EventInjector.swift`, `index.html`, or `scripts/smoke-all.sh`.

## Cycle 12 — MP-14 refuse cloud Apple Speech

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-14 | P1 | WRITE | `SpeechSession.hasOnDeviceSTT`: Whisper `isReady`/`isCached` or Apple `supportsOnDeviceRecognition`. Else `no_on_device_stt` on live start and `POST /stt`. Live/file Apple paths never set `requiresOnDeviceRecognition = false`. |
| MP-12 | P1 | YES | PROTOCOL `stt_final` reason table; SECURITY on-device-only paragraph. |

## Cycle 13 — MP-23 JSON token bucket + max 8 clients

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-23 | P2 | WRITE | `JSONRateLimit` meters `type`/`text`/`voice` (40/s burst 80). `ProtocolLimits.maxClients = 8`. Local `accept` 503 `too_many_clients`; `handleJSONText` ack `rate_limited`. Binary / key / ping untouched. Remote stub unrestored. |

## Leftover P0

None of the Cycle 7 wires exist on the GitHub stub. Local leftover:

| ID | Linux | Next step |
|---|---|---|
| MP-04 health | WRITE | `ip`/`ips`/`ifaces` stay for LAN debug. CORS echo is the recon control (local). Pairing token stays optional/off. |

## Leftover P1

| ID | Linux | Next step |
|---|---|---|
| MP-11 | WRITE | Additive `proto: 1` on local `hello` / `hello_ack` / `/health` (Cycle 10). Remote stub unrestored. |
| MP-12 | YES | Expand PROTOCOL + SECURITY to the full field/limit tables |
| MP-13 | WRITE | Cycle 11: logs count/reason only (no `text.prefix`); `Logger` sets `0600` on `/tmp/magicpad-server.log`. EventInjector redact is local-only (63 KB). |
| MP-14 | WRITE | Cycle 12: refuse `no_on_device_stt` when Whisper missing and Apple on-device unsupported. Remote SpeechSession unrestored until human push. |
| MP-15 | YES | Web a11y: tablist, single `<h1>`, `:focus-visible`, pad `role="application"` |
| MP-16 | YES | Debounced resize → layout tokens; 44/48 px touch targets |
| MP-17 | WRITE | Local `/health` uses `JSONText.encode` (sorted keys, no `\/`). Remote stub unrestored. |

## Leftover P2

| ID | Next step |
|---|---|
| MP-18 | Move binary/WS/LAN/filename parsers into `MagicPadCore` + shared fixtures |
| MP-19 | Single `Version.swift`; `build_app.sh` uses `swift build --show-bin-path` |
| MP-20 | Menu diagnostics line (proto / htmlRev / clients); cert export |
| MP-21 | Playwright 4-viewport layout on Linux |
| MP-22 | `GET /cert` (public `.cer` only) + in-page Safari/Chrome steps |
| MP-23 | Cycle 13: Core + Python bucket; local server wire. Remote stub unrestored. |
| MP-24 | Persist dictation draft in `localStorage` (clear on replace-mode ack) |

## Optional security (not scheduled)

A **pairing token** on the QR / hello is OK only if optional, default-off, and backward compatible. Do not require it without a protocol bump and tests. Never put the token in `/health`.
