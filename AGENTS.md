# MagicPad — contributor notes

LAN trackpad + on-device dictation. Voice goes to the clipboard (optional Cmd+V into the focused app). **No product LLM.**

## Do

- Treat this as a generic Mac input tool
- Keep CGEvent on public APIs (`CGEventCreate*`); do not promote left-click from travel distance
- State machine: `pending` (mouseMoved only) / `armed` (hold ~280ms, jitter ≤14px) / `multi`
- Phone client: TouchEvents over PointerEvents for multi-touch
- Build with `nice -n 19` when compiling in the background

## Do not

- Bind Grok / Claude / Cursor / any cloud LLM in the product UI
- Add an “ask AI” button
- Bake a LAN IP, home path, hostname, or personal email into source, QR, docs, or `/health`

## Layout

```
MagicPadServer/     SwiftPM menu-bar app (CGEvent + WhisperKit)
MagicPadClient/     single-file phone page
MagicPadIOS/        optional native haptic bits
scripts/            build_app.sh, smoke, fetch-whisper-model.sh
docs/               architecture and smoke notes
build/              gitignored .app output
```

## Protocol (short)

- 13-byte single-finger / 18-byte multi-finger binary frames, little-endian
- JSON: `voice` / `stt` / `type` / `key`
- HTTP `:7878` for the pad; HTTPS `:7879` for getUserMedia dictation

See `docs/architecture.md` and `README.md`.
