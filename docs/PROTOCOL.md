# MagicPad protocol (seed)

Canonical layout also in `docs/architecture.md`. This file is the field/limit catalogue; Cycle 1 ships the voice clamp and JSON types used by smokes. Additive `proto: 1` is on local `hello` / `hello_ack` / `/health` (MP-11).

**Do not change 13B/18B layout without tests, docs, and owner sign-off.**

## Binary (little-endian)

| Bytes | Use |
|---|---|
| 13 | Single finger: `phase u8` · `dx i16` · `dy i16` · `pressure u8` · `buttons u8` · `t_ms u32` · `seq u16` |
| 18 | Multi finger: 13-byte prefix + `fingers u8` · `gesture u8` · `ext i16` (pinch scale×1000, mission dir, …) |
| 6 | Latency echo (server → phone): `seq u16` · `t_ms u32` copied from the inbound 13-byte frame |

Phases: 0 down · 1 move · 2 up · 3 cancel · 10 double · 11 right · 20 scroll · 21 pinch · 22 triple · 23 smart zoom · 24 mission/desktop. State machine `pending` / `armed` / `multi` — never promote left-click from travel distance.

## JSON text frames

| `type` | Inbound fields | Ack |
|---|---|---|
| `hello` | `ua`, `ts`, optional `proto` | `hello_ack{ok, ts, htmlRev, ax, clients, proto}` |
| `ping` | `ts` | `pong{ts, serverTs}` |
| `key` | `action` (allowlist + aliases), `count`/`repeat` 1…200 | `voice_ack{ok, reason}` — `empty_action` `bad_action` `bad_count` `unknown_action` or canonical action |
| `type` / `text` | `text` string, max **2000** graphemes | `empty_type` `bad_type` `type` `type_truncated` |
| `voice` | `text` string, max **20000** graphemes; `lang` ∈ zh-CN, en-US, ja-JP (else zh-CN); `mode` ∈ append, replace (else append); `autoPaste` JSON bool (else true) | `empty` · `bad_voice` (non-string `text`, no inject) · `voice_truncated` (ok, clipboard wrote the prefix) · `ax_denied_clipboard_ok` · `append`/`replace` |
| `classify` | `kind`, `reason`, `phase` | `classify_ack` — telemetry only, **no inject** |
| `stt` | `action` start/stop/status | `stt_status` / `stt_final` — on-device only (`no_on_device_stt` if Whisper missing and Apple on-device unsupported) |

Unknown JSON `type` is ignored. Non-object / non-string `type` is ignored.

### Inbound `type` allowlist (Cycle 27)

`WSType.parse` / `parse_ws_type`: exact `voice` · `key` · `type` · `text` · `stt` · `hello` · `ping` · `classify`. Trim only; case-sensitive. Unknown / missing → ignore (no inject). HTTP `POST /drop` is not a WS type.

### hello / ping (MP-12)

`hello` inbound: `ua` string, `ts` number, optional `proto` (additive; missing is fine).  
`hello_ack`: `ok`, `ts`, `htmlRev`, `ax`, `clients`, `proto`. No pairing token.  
`ping` inbound: `ts`. `pong`: `ts`, `serverTs`. Binary 6-byte latency echo is separate (`seq`, `t_ms`).

### `key` allowlist (MP-12)

Canonical `action` values. Aliases live in `scripts/fixtures/key-aliases.json` (and the Swift table). Empty → `empty_action`. Non-string → `bad_action`. Unknown non-empty → `unknown_action`. `count`/`repeat` outside 1…200 → `bad_count`.

`backspace` `wordBackspace` `wordForwardDelete` `wordLeft` `wordRight` `selectLeft` `selectRight` `selectWordLeft` `selectWordRight` `selectUp` `selectDown` `selectHome` `selectEnd` `selectPageUp` `selectPageDown` `lineStart` `lineEnd` `selectLineStart` `selectLineEnd` `lineBackspace` `lineForwardDelete` `clearField` `selectAll` `left` `right` `up` `down` `enter` `unstick` `delete` `forwardDelete` `escape` `tab` `home` `end` `pageUp` `pageDown` `cut` `copy` `paste` `undo` `redo` `showDesktop` `missionControl` `launchpad` `notificationCenter` `lookUp` `openAccessibility`

### `voice_ack` reasons (MP-12)

| `reason` | `ok` | Meaning |
|---|---|---|
| `append` / `replace` | true | Clipboard wrote; paste if AX on |
| `voice_truncated` | true | Prefix of 20000 graphemes wrote; remainder dropped |
| `rate_limited` | false | Cycle 13 token bucket; no inject |
| `empty` / `bad_voice` | false | Missing or non-string `text` |
| `ax_denied` / `ax_denied_clipboard_ok` | false / mixed | Need Accessibility; clipboard may still have held |
| `empty_action` / `bad_action` / `bad_count` / `unknown_action` | false | `key` parse |
| `empty_type` / `bad_type` / `type` / `type_truncated` | mixed | `type`/`text` clamp |
| `launchpad_fail` / `showDesktop_fail` / `notificationCenter_fail` / `clipboard` | false | System key or pasteboard write |

### `classify` (telemetry only)

Inbound `kind` / `reason` / `phase` (optional `net` `path` `ms` `scale`). Ack `classify_ack`. **Never injects.**

A pairing token on QR / `hello` is optional and default-off. Never put a token in `/health`.

### Pairing hatch (Cycle 20)

Env `MAGICPAD_PAIRING_TOKEN` empty → off (current product). When set, `hello` must send `pair` equal to that value or the ack is `hello_ack{ok:false, reason:pairing_rejected}`. The token is never a `/health` key. Cycle 29: `PairingToken.healthAllowsKey` / `health_allows_key`. Local `WebSocketServer` hello wire; remote stub unrestored.

### QR never embeds the token (Cycle 21)

`scripts/generate_qr.py` and runtime `QRImageLoader.mobileURL` encode only `{scheme}://{ip}:{port}/` plus optional `?auto=1&host={ip}`. They must never contain `pair=`, `MAGICPAD_PAIRING_TOKEN`, or the env token value. `--pair` is refused. Pairing stays a `hello.pair` field when the env hatch is on.

`maxVoiceChars` is 20000 while `maxTypeChars` is 2000 because voice lands on the pasteboard and is not `keySerial`-bound. Type injects keystrokes on the inject serial. Cycle 13 meters `type` / `text` / `voice` with `JSONRateLimit` (40/s, burst 80). Over the burst the ack is `voice_ack{ok:false, reason:rate_limited}` and nothing is injected. `key` / `ping` / `hello` / `stt` / `classify` and every binary 13/18-byte frame are **not** metered.

## HTTP

| Route | Notes |
|---|---|
| `GET /` | Phone page (bundled `index.html`) |
| `GET /health` | Unauthenticated JSON via `JSONText.encode` (local). Keys include `proto`. `ip`/`ips`/`ifaces` stay for LAN debug; CORS echo is the recon control. No-home-path / no-hostname promise is **this route only** — see `docs/SECURITY.md` |
| `POST /stt` | ≤ 10 MB audio. Cycle 7 wired `HTTPPostOrigin.allows` locally (403 `origin_rejected`). Cycle 12 refuses `no_on_device_stt` when Whisper is missing and Apple on-device is unsupported. Remote stub unrestored. |
| `POST /drop` | ≤ 50 MB file → pasteboard + optional Cmd+V (`autoPaste` default true). Same local Origin check as `/stt`. |
| `GET /cert` | Cycle 15 (MP-22): public DER only (`magicpad-lan.cer`, `application/x-x509-ca-cert`, `Content-Disposition` attachment). Exact `/cert`. Missing file → 404 `cert_not_ready`. `.pem` / `.p12` / `.key` paths → 404 `cert_forbidden`. Never those secret files. Local `WebSocketServer` wire; remote stub unrestored. |

### `GET /health` keys (smoke-all contract + `proto`)

`ok` `service` `port` `httpPort` `httpsPort` `https` `httpsUrl` `httpUrl` `httpsError` `ip` `ips` `ifaces` `routeIface` `mdns` `html` `htmlPath` `htmlSource` `htmlRev` `binaryPath` `injectQueue` `ax` `stt` `sttFile` `whisper` `whisperReady` `whisperCached` `whisperModel` `lastKey` `lastKeyReason` `injectCount` `lastKeyOk` `lastKeyAt` `lastKeyCount` `lastDropOk` `lastDropReason` `lastDropKind` `lastDropAt` `dropCount` `lastGesture` `lastGestureReason` `lastGestureAt` `lastGesturePhase` `gestureCount` `clients` `ts` `proto`.

Never hostname, home path, SSID, user, or payload text. `binaryPath` is `MagicPad.app` only.

### `stt` JSON (MP-12)

Inbound: `type=stt`, `action` ∈ `start`/`begin`/`on` · `stop`/`end`/`off` · `status`. Optional `lang` (zh-CN / en-US / ja-JP; else zh-CN). Optional `onDevice` JSON bool (else true). Unknown action → `stt_final{ok:false, reason:bad_action}` (no inject). Cycle 23: `STTAction.parse`. Cycle 24: `STTLang.parse`. Cycle 25: `STTOnDevice.parse` (JSON bool only; else true). Local wire uses Core; remote stub unrestored.

`stt_status` (status / live): `state` listening|idle|already, `lang`, `engine` whisper|apple, optional `auth` `onDeviceSupported` `whisperReady` `whisperModel`.

`stt_final`: `ok`, `text`, `reason` (table below), `lang`, `engine` whisper|apple|none, `onDevice` true on success. Cloud Apple Speech is not a fallback (`no_on_device_stt`).

## `stt_final` reasons

| `reason` | Meaning |
|---|---|
| `no_on_device_stt` | Whisper weights missing (`!isReady && !isCached`) and Apple `supportsOnDeviceRecognition` is false. Cloud Apple Speech is not a fallback. |
| `mic_denied` | Mac microphone permission denied |
| `speech_denied` / `speech_restricted` / `speech_auth_required` | Speech authorization |
| `empty` / `empty_body` / `too_large` | No audio, or POST body over 10 MB |
| `recognizer_unavailable` / `no_input_device` | Apple recognizer or input hardware missing |
| `whisper_fail` / `whisper_write` | Whisper path failed before a legal Apple on-device fallback |
| `cancelled` / `timeout` / `no_speech` | Session ended without a transcript |

`engine` is `whisper`, `apple`, or `none`. `onDevice` is always true on success.

## Limits (`MagicPadCore.ProtocolLimits` / `scripts/magicpad_proto.py`)

| Constant | Value | Where |
|---|---|---|
| `maxFrameBytes` | 1 048 576 (1 MiB) | WS `parseFrame` — Cycle 7 wired locally (`pendingCloseCode` then close after unlock). Remote stub unrestored. |
| `maxHeaderBytes` | 16 384 | pre-handshake header — Cycle 7 wired (431 if over cap without `\\r\\n\\r\\n`) |
| `maxTypeChars` | 2 000 | `type` / `text` JSON |
| `maxVoiceChars` | 20 000 | `voice` JSON (pasteboard) |
| `proto` | 1 | additive on local `hello` / `hello_ack` / `/health` (MP-11). Remote stub unrestored. |
| `requiredWebSocketVersion` | `13` | handshake 426 if missing — Cycle 7 wired locally |
| allowed opcodes | 0x0 0x1 0x2 0x8 0x9 0xA | close 1003 on others — Cycle 7 wired locally. `0x0` is listed so fragmented browsers are not disconnected; reassembly is not implemented |
| `maxClients` | 8 | Cycle 13 wired locally: 9th TCP accept is HTTP 503 `too_many_clients` (no WS upgrade). Remote stub unrestored. |
| `jsonTokensPerSec` / `jsonBurst` | 40 / 80 | Cycle 13: `type`/`text`/`voice` only. Ack `rate_limited`. Never throttle binary 120 Hz. |
| binary payload | 7 / 13 / 18 bytes | Cycle 26: `BinaryFrame.parse` / `parse_binary_frame`. &lt;7 → drop (no inject). 13-byte pointer (phase/dx/dy/pressure/buttons/tMs/seq). 18-byte gesture adds fingers/gesture/ext. Phases: 0 down · 1 move · 2 up · 3 cancel · 10 dbl · 11 right · 20 scroll · 21 pinch · 22 triple · 23 smartzoom · 24 mission. Unknown phase stays `unknown`. Local inject + latency echo use Core; remote stub unrestored. |

Wiring notes: `docs/CYCLE4-WIRING.md`. HTTP Origin: `docs/CYCLE3-HTTP-ORIGIN.md`.

CORS: curl without `
Origin` still sees `Access-Control-Allow-Origin: *` (smoke-all). `CORSPolicy.accessControl` echoes an allowlisted Origin (`needsVary == true`) and omits ACAO for evil Origins. Echo-allowlist does **not** stop a CORS-simple `no-cors` POST write — that is `HTTPPostOrigin.allows` in local `beginHTTPPost`.

## htmlRev

Client constant `MAGICPAD_HTML_REV` format `YYYYMMDD-HHMM-hN`. Server `/health.htmlRev` must match the bundled file. Mismatch → phone hard-refresh.
