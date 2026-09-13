# MagicPad protocol (seed)

Canonical layout also in `docs/architecture.md`. This file is the field/limit catalogue; Cycle 1 ships the voice clamp and JSON types used by smokes. Additive `proto` versioning is leftover (MP-11).

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
| `hello` | `ua`, `ts` | `hello_ack{ok, ts, htmlRev, ax, clients}` |
| `ping` | `ts` | `pong{ts, serverTs}` |
| `key` | `action` (allowlist + aliases), `count`/`repeat` 1…200 | `voice_ack{ok, reason}` — `empty_action` `bad_action` `bad_count` `unknown_action` or canonical action |
| `type` / `text` | `text` string, max **2000** graphemes | `empty_type` `bad_type` `type` `type_truncated` |
| `voice` | `text` string, max **20000** graphemes; `lang` ∈ zh-CN, en-US, ja-JP (else zh-CN); `mode` ∈ append, replace (else append); `autoPaste` JSON bool (else true) | `empty` · `bad_voice` (non-string `text`, no inject) · `voice_truncated` (ok, clipboard wrote the prefix) · `ax_denied_clipboard_ok` · `append`/`replace` |
| `classify` | `kind`, `reason`, `phase` | `classify_ack` — telemetry only, **no inject** |
| `stt` | `action` start/stop/status | `stt_status` / `stt_final` — on-device only |

Unknown JSON `type` is ignored. Non-object / non-string `type` is ignored.

`maxVoiceChars` is 20000 while `maxTypeChars` is 2000 because voice lands on the pasteboard and is not `keySerial`-bound. Type injects keystrokes on the inject serial; a 10× clipboard clamp is defensible and currently unthrottled by the JSON token bucket (MP-23 leftover).

## HTTP

| Route | Notes |
|---|---|
| `GET /` | Phone page (bundled `index.html`) |
| `GET /health` | Unauthenticated JSON; no-home-path / no-hostname promise is **this route only** — see `docs/SECURITY.md` |
| `POST /stt` | ≤ 10 MB audio. **No Origin check yet** (Cycle 3: `docs/CYCLE3-HTTP-ORIGIN.md`) |
| `POST /drop` | ≤ 50 MB file → pasteboard + optional Cmd+V (`autoPaste` default true). **No Origin check yet** — MP-01 did not close this door |

## Limits (`MagicPadCore.ProtocolLimits` / `scripts/magicpad_proto.py`)

| Constant | Value | Where |
|---|---|---|
| `maxFrameBytes` | 1 048 576 (1 MiB) | WS `parseFrame` — Cycle 7 wired locally (`pendingCloseCode` then close after unlock). Remote stub unrestored. |
| `maxHeaderBytes` | 16 384 | pre-handshake header — Cycle 7 wired (431 if over cap without `\\r\\n\\r\\n`) |
| `maxTypeChars` | 2 000 | `type` / `text` JSON |
| `maxVoiceChars` | 20 000 | `voice` JSON (pasteboard) |
| `proto` | 1 | additive on `hello` / `hello_ack` / `/health` (MP-11 leftover) |
| `requiredWebSocketVersion` | `13` | handshake 426 if missing — Cycle 7 wired locally |
| allowed opcodes | 0x0 0x1 0x2 0x8 0x9 0xA | close 1003 on others — Cycle 7 wired locally. `0x0` is listed so fragmented browsers are not disconnected; reassembly is not implemented |

Wiring notes: `docs/CYCLE4-WIRING.md`. HTTP Origin: `docs/CYCLE3-HTTP-ORIGIN.md`.

CORS: curl without `Origin` still sees `Access-Control-Allow-Origin: *` (smoke-all). `CORSPolicy.accessControl` echoes an allowlisted Origin (`needsVary == true`) and omits ACAO for evil Origins. Echo-allowlist does **not** stop a CORS-simple `no-cors` POST write. The HTTP Origin check is leftover Cycle 3, not a CORS header change.

## htmlRev

Client constant `MAGICPAD_HTML_REV` format `YYYYMMDD-HHMM-hN`. Server `/health.htmlRev` must match the bundled file. Mismatch → phone hard-refresh.
