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
| `voice` | `text` string, max **20000** graphemes; `lang` ∈ zh-CN, en-US, ja-JP (else zh-CN); `mode` ∈ append, replace (else append); `autoPaste` JSON bool (else true) | `empty` · `voice_truncated` (ok, clipboard wrote the prefix) · `ax_denied_clipboard_ok` · `append`/`replace` |
| `classify` | `kind`, `reason`, `phase` | `classify_ack` — telemetry only, **no inject** |
| `stt` | `action` start/stop/status | `stt_status` / `stt_final` — on-device only |

Unknown JSON `type` is ignored. Non-object / non-string `type` is ignored.

## HTTP

| Route | Notes |
|---|---|
| `GET /` | Phone page (bundled `index.html`) |
| `GET /health` | Unauthenticated JSON; see `docs/SECURITY.md` |
| `POST /stt` | ≤ 10 MB audio |
| `POST /drop` | ≤ 50 MB file → pasteboard |

CORS: curl without `Origin` still sees `Access-Control-Allow-Origin: *` (smoke-all). Reflect-allowlist is leftover MP-04.

## htmlRev

Client constant `MAGICPAD_HTML_REV` format `YYYYMMDD-HHMM-hN`. Server `/health.htmlRev` must match the bundled file. Mismatch → phone hard-refresh.
