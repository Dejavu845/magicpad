# MagicPad engineering

Durable operating notes for humans and Cloud Agents. Product copy stays in `README.md`. Contributor hard rules stay short in `AGENTS.md`. Protocol bytes live in `docs/architecture.md` plus `docs/PROTOCOL.md`. Threat model: `docs/SECURITY.md`.

This Linux Cloud Agent **cannot** compile the menu-bar app (no Xcode / macOS SDK). It **can** edit HTML/JS, Python smokes, docs, `MagicPadCore` (write-only Swift), and GitHub Actions that run on `ubuntu-latest`.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Mac server | SwiftPM 6.2, macOS 13+, `MenuBarExtra` | Targets: `MagicPadCore` (Foundation only), `MagicPadServer` (AppKit + Network + CGEvent + WhisperKit), `MagicPadServerTests` (Core only) |
| Transport | Hand-rolled RFC 6455 over `NWListener` | HTTP `:7878` pad; HTTPS `:7879` getUserMedia. LAN bind only |
| Inject | Public `CGEventCreate*` / `CGEventPost` | State machine `pending` / `armed` / `multi`. Never promote left-click from travel distance |
| STT | WhisperKit on-device (base → tiny) | Weights gitignored (`vendor/whisper/`). No cloud STT / no LLM |
| Phone UI | Single-file `MagicPadClient/index.html` | Vanilla JS, TouchEvents (not PointerEvents for the pad), no bundler, no CDN |
| Pack | `scripts/build_app.sh` | Ad-hoc sign, `LSUIElement`, bundles HTML (+ Whisper if present) |
| Linux gates | `lint-repo.sh` (incl. file-integrity floors), `check-html.py`, `test-protocol.py` | GitHub Actions `linux-checks` on every push |

Do not add: NIO/Vapor, React, a phone App Store app, ngrok/cloudflared, OpenAI/Anthropic/Grok SDKs.

## UI / UX principles

- QR is always **HTTP `:7878`**. HTTPS is a second step inside the page (self-signed). Friends must not hit a certificate wall first.
- Host comes from `location.hostname`. Ignore stale `?host=` when the page is not loopback.
- Connection chrome must tell the truth: reconnecting, AX off, stale `htmlRev`, airplane. Do not invent “AI thinking” states.
- Voice ends at the Mac clipboard (optional Cmd+V). Copy says 听写 / Whisper 转写, never “AI”.
- Pad gestures: TouchEvents, first packet of a frame sent immediately, remaining coalesced on rAF (not a new filter).
- Layout tokens (`phone-port` / `phone-land` / `tablet-port` / `tablet-land`) from window min-side, never UA sniffing (haptics UA parse is the one documented exception).
- Menu bar: QR first, Accessibility second. No account UI, no public-URL toggle.

Every `index.html` edit bumps `MAGICPAD_HTML_REV` (`YYYYMMDD-HHMM-hN`, N strictly increases).

## Coding standards

### Security (LAN injector)

- Listeners only when a private IPv4 is present. No UPnP, no tunnel.
- WebSocket `Origin` allowlist (`OriginPolicy`): missing Origin allowed (curl/python smokes); empty `Origin:` header is **rejected today** by the server parser (literal `"Origin"`), while the policy function treats `""` as allow — see `docs/SECURITY.md`. `http(s)|ws(s)` + host in `{127.0.0.1, localhost, ::1} ∪ LAN IPs`. Else `403`. Debug hatch: `MAGICPAD_ALLOW_ANY_ORIGIN=1` (off by default). **HTTP `POST /drop` and `POST /stt` have no Origin check yet** (`docs/CYCLE3-HTTP-ORIGIN.md`).
- Inbound inject strings go through pure `MagicPadCore` parsers (`parseKey` / `parseType` / `parseVoice`). Allowlist + clamps. No `as? String` then inject. Non-string voice `text` → `bad_voice` (not `empty`).
- `/health` JSON must not leak home paths, hostname, SSID, or payload text. `binaryPath` is `MagicPad.app` only. HTML error pages are **not** covered by that promise.
- Never commit `*.p12` `*.pem` `*.key` `*.cer`, Whisper `*.mlmodelc` / `weight.bin`, or `.env*`.

### Swift

- Pure logic → `MagicPadCore` (`import Foundation` only) + XCTest.
- Shared mutable state: `@MainActor`, `InjectRuntime` serial queue, or `NSLock`.
- Log lengths and reasons, not dictated text.
- Build with `nice -n 19 swift build` on the owner Mac.

### HTML / JS

- One `<style>`, one `<script>`. Must pass `node --check` on the extracted script (`check-html.py`).
- Network/user strings: `textContent` or `escapeHtml()`. Host: `isValidHost` after stripping scheme/port.
- TouchEvents on the pad. PointerEvents only on buttons.

### Python / shell

- Stdlib first. Optional imports `sys.exit(2)` with an install hint.
- Bash: `set -euo pipefail`, `shellcheck -S warning`. Exit 0 PASS / 1 FAIL / 2 environment.
- Mac-only tools (`pbpaste`, `say`, `codesign`) must SKIP or exit 2 on Linux, never crash the Linux gate.

## Workflow

### Owner Mac — first run

```bash
git clone https://github.com/Dejavu845/magicpad.git && cd magicpad
./scripts/fetch-whisper-model.sh          # optional; first 听写 can also cache
cd MagicPadServer && nice -n 19 swift build && cd ..
./scripts/build_app.sh                    # → build/MagicPad.app
open build/MagicPad.app
```

Then: 系统设置 → 隐私与安全性 → 辅助功能 → MagicPad. Scan the **current** menu QR on the same Wi‑Fi. Details: `docs/ACCESSIBILITY.md`, `docs/SHARE-APP.md`.

HTML-only (keeps the AX checkbox): `./scripts/build_app.sh --html-only`.

### Smoke (Mac, app running)

```bash
./scripts/smoke-all.sh                    # HTTP /health contract + ws + type + isolated HTTPS WARN
python3 scripts/smoke-https.py            # WARN-level TLS
# device: docs/SMOKE-DEVICE.md
```

`BASE_URL` / `BASE_HOST` / `BASE_PORT` override the loopback default. HTTPS is isolated so a TLS stall does not fail HTTP smoke.

### Linux Cloud Agent / CI

```bash
./scripts/lint-repo.sh
python3 scripts/check-html.py MagicPadClient/index.html
python3 -m unittest scripts/test-protocol.py -v
python3 scripts/generate_qr.py --print-only --http
```

Environment bootstrap: `.cursor/environment.json` installs `shellcheck`, `websocket-client`, `qrcode[pil]`. Swift is optional — install must **not** fail if the toolchain or macOS frameworks are missing.

`lint-repo.sh` also floors `WebSocketServer.swift` / `index.html` / `smoke-all.sh` / `KeyProtocol.swift` and rejects any `Sources/**/*.swift` containing `Placeholder replaced by`. A 140-byte stub (today's remote tree) is proven to fail via `python3 scripts/repo_integrity.py --prove-stub`.

### Share

Copy `build/MagicPad.app`. The other person runs it on **their** Mac, same LAN, scans **their** menu QR. No public URL. See `docs/SHARE-APP.md`.

### CI

`.github/workflows/linux-checks.yml` runs the Linux gates on every push/PR. Mac gates (`swift test`, `build_app.sh`, `smoke-all.sh`) are owner-run until a macOS runner is added.
