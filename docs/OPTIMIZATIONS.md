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
| MP-04 echo | P0 | WRITE | `CORSPolicy.accessControlAllowOrigin` — echo allowlist / omit / `*`. **Not the write control.** |
| H1 helper | P0 | WRITE | `HTMLEscape.escape` + CSP/nosniff constants for `fallbackHTML`. |
| MP-17 seed | P1 | WRITE | `JSONText.encode` (sorted keys). |
| MP-18 seed | P2 | WRITE | `LANAddress.isPrivate` + `Filenames.sanitize` + Python mirrors. |

## Cycle 5 — Opus C3 follow-up (docs + mirror fidelity)

| ID | Pri | Linux | What landed |
|---|---|---|---|
| MP-28 parity | P1 | YES | Fixture comment + `test_every_fixture_origin_appears_in_swift`; added `localhost-suffix` and four empty query/fragment/userinfo rows to the Swift table |
| MP-28 mirror | P1 | YES | Python `origin_parse` rejects raw `?`/`#` and `username is not None` so empty query/fragment/userinfo match Swift |
| MP-28 docs | P1 | YES | `SECURITY.md` present tense + decode-then-compare note; `HTTPPostOrigin.swift` states the helper is not yet called |

## Leftover P0

| ID | Linux | Next step |
|---|---|---|
| MP-02 wire | WRITE | After restoring `WebSocketServer.swift`, insert `ProtocolLimits` in `parseFrame` / header / version (`docs/CYCLE4-WIRING.md`) |
| MP-04 write | WRITE | **`HTTPPostOrigin.allows` in `beginHTTPPost` before pasteboard/STT** (`docs/CYCLE3-HTTP-ORIGIN.md`). CORS echo is *not* sufficient. `/health` wildcard CORS is a recon oracle (`ip`/`ips`/`ifaces`). |

## Leftover P1

| ID | Linux | Next step |
|---|---|---|
| MP-11 | WRITE | Additive `proto: 1` on `hello` / `hello_ack` / `/health` |
| MP-12 | YES | Expand PROTOCOL + SECURITY to the full field/limit tables |
| MP-13 | WRITE | Redact voice/type text in logs; `0600` on `/tmp/magicpad-server.log` |
| MP-14 | WRITE | If Whisper missing and Apple on-device STT unsupported, refuse (`no_on_device_stt`) |
| MP-15 | YES | Web a11y: tablist, single `<h1>`, `:focus-visible`, pad `role="application"` |
| MP-16 | YES | Debounced resize → layout tokens; 44/48 px touch targets |
| MP-17 | WRITE | Build `/health` with `JSONSerialization` (keep every smoke-all key) |

## Leftover P2

| ID | Next step |
|---|---|
| MP-18 | Move binary/WS/LAN/filename parsers into `MagicPadCore` + shared fixtures |
| MP-19 | Single `Version.swift`; `build_app.sh` uses `swift build --show-bin-path` |
| MP-20 | Menu diagnostics line (proto / htmlRev / clients); cert export |
| MP-21 | Playwright 4-viewport layout on Linux |
| MP-22 | `GET /cert` (public `.cer` only) + in-page Safari/Chrome steps |
| MP-23 | Max 8 WS clients; JSON token bucket (never throttle binary 120 Hz) |
| MP-24 | Persist dictation draft in `localStorage` (clear on replace-mode ack) |

## Optional security (not scheduled)

A **pairing token** on the QR / hello is OK only if optional, default-off, and backward compatible. Do not require it without a protocol bump and tests. Never put the token in `/health`.
