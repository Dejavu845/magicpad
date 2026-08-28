# MagicPad — Research Next

**Date**: 2026-08-08  
**Scope**: research + design notes only (no product code changes in this pass)  
**Hard constraints** (from `AGENTS.md`): no product LLM agents; voice is pass-through only (clipboard + optional Cmd+V); CGEvent public APIs preferred; TouchEvents on client.

Related session log: [`SESSION-NIGHT-LOG.md`](./SESSION-NIGHT-LOG.md).

---

## 1) Why multi-device LAN HTTP can fail

MagicPad serves the client over plain **HTTP :7878** and events over **WebSocket `ws://host:7878`**. Both require **same-L2/L3 reachability** between phone and Mac. Failures cluster into privacy policy, relay/VPN, Wi‑Fi isolation, wrong host, and Accessibility (AX) after rebuild.

### Failure modes

| # | Mode | Symptom | Why |
|---|---|---|---|
| A | **iOS Local Network privacy** | Safari loads blank / WS never opens; first open may prompt once | iOS 14+ requires Local Network permission for apps (incl. Safari) that talk to private LAN hosts. Denied → local HTTP/WS blocked. Toggle: Settings → Privacy & Security → Local Network → Safari (and any PWA wrapper). See [Apple Support 102229](https://support.apple.com/en-us/102229). |
| B | **macOS Local Network (Sequoia+)** | Phone can ping nothing useful; Mac outbound Bonjour/LAN oddities | macOS Sequoia added Local Network privacy similar to iOS. Menu-bar apps may need allow in System Settings → Privacy & Security → Local Network for MagicPad. |
| C | **iCloud Private Relay / Limit IP Address Tracking** | Internet OK; some DNS / captive-portal weirdness; **local IPs usually unaffected** | Apple documents that **local network traffic and private domains are not protected by Private Relay** — so pure `http://192.168.x.x:7878` often still works. Confusion is common: users disable Private Relay when the real issue is isolation or wrong IP. Private Relay can still break **Pi-hole / enterprise DNS** for public names; for MagicPad prefer numeric IP over flaky `.local`. |
| D | **Private Wi‑Fi Address (MAC rotation)** | Rare: MAC-filtered routers drop client | Settings → Wi‑Fi → ⓘ → Private Wi‑Fi Address. Not usually a MagicPad-specific issue unless the AP uses MAC ACL. |
| E | **Guest Wi‑Fi / AP (client) isolation** | Phone loads nothing from Mac LAN IP; `curl` from phone fails; mDNS never resolves | Guest SSIDs and “AP isolation / client isolation” **block client↔client** traffic. MagicPad **requires** phone↔Mac unicast on TCP 7878. Fix: put both on the same non-isolated SSID (main home LAN). |
| F | **Wrong IP / wrong interface** | QR opens dead host; WS to 127.0.0.1 from phone | `LANDetector` picks first private IPv4 from `getifaddrs` (skips lo/awdl/llw/utun). Multi-homed Macs (Thunderbolt bridge, Docker, VPN `utun`, multiple Wi‑Fi) can show a **non-phone-reachable** address. Prefer en0 Wi‑Fi IP that matches the phone’s subnet. |
| G | **`.local` mDNS fails** | `http://hostname.local:7878` times out; IP works | Safari/iOS mDNS is flaky across VLANs, guest isolation, or when multicast is filtered. Architecture already notes Bonjour discovery is weak in browser (`navigator.mdns` not available). **Numeric IP + `?host=` is the reliable path** (P0-1). |
| H | **VPN / always-on proxy on phone or Mac** | Split-tunnel drops LAN; full-tunnel may still allow RFC1918 | Phone VPN can blackhole `192.168/10/172.16`. Temporarily disconnect VPN. Mac-side HTTPS_PROXY is documented as **external only** — should not affect local WS, but third-party VPN clients may still capture LAN. |
| I | **HTTP mixed content / HTTPS page** | WS blocked if page ever served under HTTPS | MagicPad is HTTP-only on LAN. Do not front with HTTPS CDN for the pad page without WSS. Scanning QR must open `http://…`. |
| J | **Firewall** | One direction fails | macOS Application Firewall / third-party firewall must allow MagicPadServer inbound TCP 7878. Corporate MDM profiles may block. |
| K | **Accessibility (AX) looks like “LAN failure”** | Page connects, cursor doesn’t move, right-click silent | Not network: CGEvent inject needs Accessibility. **Rebuild + re-codesign often clears the checkbox** — see `docs/ACCESSIBILITY.md`. User may report “phone can’t control Mac” when WS is fine. |
| L | **Chrome Local Network Access (desktop)** | Future: permission prompt for sites hitting private IPs | Chrome is rolling out LNA prompts (2025+). Android Chrome on LAN IP today is usually fine; watch for new prompts on multi-device tests (P1-6). |

### Actionable checklist (user + agent)

Copy this into smoke / support flows:

```
[ ] Phone and Mac on SAME SSID (not Guest / IoT / Hotel)
[ ] Router: AP isolation / client isolation OFF on that SSID
[ ] Phone: Settings → Privacy → Local Network → Safari = ON
[ ] Mac (Sequoia+): Privacy → Local Network → MagicPad = ON (if listed)
[ ] Prefer QR / URL with numeric IP, e.g. http://192.168.x.y:7878/?host=192.168.x.y
[ ] Confirm subnet match: phone Wi‑Fi IP same /24 (or same VLAN) as Mac
[ ] Mac: ifconfig / LANDetector shows the Wi‑Fi en* IP, not Docker/bridge
[ ] curl from phone browser or another LAN device: http://<mac-ip>:7878/ → HTML 200
[ ] Mac Accessibility: MagicPad checked after every rebuild (AX ≠ LAN)
[ ] Disable phone VPN / Private Relay only if DNS/.local is broken; keep numeric IP first
[ ] Port 7878 free; only one MagicPadServer instance
[ ] WS URL must be ws://<same-host>:7878 (client derives host from ?host= or location.hostname)
```

### Product implications (later, not this pass)

- Surface **subnet mismatch** and **connection refused** with human copy, not only “已断开”.
- Menu bar: show **all** candidate LAN IPs + “which one is Wi‑Fi”.
- Keep `?host=` and full-`out`-style absolute URLs on QR forever.
- Optional: simple `/health` JSON with server IP list for multi-device debug (P0-9 adjacent).

---

## 2) Apple trackpad gesture table vs MagicPad gaps

Sources: [Apple Multi-Touch gestures](https://support.apple.com/en-us/102482), MagicPad protocol in `AGENTS.md`, client `index.html`, server `EventInjector.swift` / `WebSocketServer.swift`.

**Injection reality**: MVP uses **CGEvent** (mouse, scroll wheel, key combos). True trackpad multi-touch (IOKit HID multitouch descriptor) is Phase 4 — three/four-finger **system** gestures are emulated via **keyboard shortcuts** (Ctrl+Arrow, Cmd+=/−, etc.), not real trackpad packets. That means apps that only listen to trackpad gesture events (not shortcuts) will not match a physical Magic Trackpad.

### Comparison table

| Apple trackpad gesture | Default system effect | MagicPad today | Gap / notes |
|---|---|---|---|
| 1-finger move | Move pointer | ✅ pending → `mouseMoved` only | Fixed “slide selects text” (P0-2) |
| 1-finger tap | Click | ✅ down+up | — |
| 1-finger double-tap | Double-click / word | ✅ phase 10 | — |
| 1-finger triple-tap | Triple-click / paragraph | ⚠️ phase 22 exists server-side | **Client may not emit triple-tap sequence** — verify / wire |
| Force Click / deep press | Look up, Quick Look | ❌ | No force on phone screen; optional long-press menu later |
| 1-finger hold + drag | Drag / select | ✅ long-press ~280ms → armed | Thresholds: `PRESS_HOLD_MS`, wiggle 14px |
| 2-finger click/tap | Secondary click | ✅ phase 11 (gesture + button); Control+left inject | P1-1 stability (deadzone vs scroll) |
| 2-finger scroll | Scroll | ✅ phase 20 + inertia fling | Line conversion `dx/10` may feel stepped |
| 2-finger pinch | Zoom | ⚠️ phase 21 → **Cmd+= / Cmd+−** | Not continuous magnify event; app-dependent |
| 2-finger rotate | Rotate image | ❌ | No phase; would need key or app-specific |
| 2-finger double-tap | Smart zoom | ✅ phase 23 → Cmd+0 | Approximation of smart zoom toggle |
| 2-finger swipe between pages | Browser back/forward | ✅ via 2-finger scroll | 横向滚动即系统「翻页」；不另绑 Cmd+[ |
| 2-finger edge → Notification Center | Notification Center | ✅ 右缘双指左滑 | `notificationCenter`：AX 点菜单栏时钟 |
| 3-finger drag | Drag window/item (AX setting) | ❌ | 三指走系统 swipe，不改成拖窗口 |
| 3-finger tap | Look up / data detectors | ✅ 三指轻点 | Ctrl+Cmd+D |
| 3-finger swipe up/down/L/R | Mission Control / Exposé / Spaces | ✅ phase 24 | 上 MC.app · 下 Exposé · 左右切桌面 |
| 4-finger swipe | 与三指相同（系统默认 3 或 4） | ✅ 同 phase 24 | H19 起不再把上滑当成显示桌面 |
| Thumb+3 pinch → Launchpad | Launchpad | ✅ 四指捏合 | `launchpad` |
| Thumb+3 spread → Show Desktop | Show Desktop | ✅ 四指张开 | Mission Control 1 |
| Natural scroll direction | Preference | Partial | Client negates 2-finger center delta; no Mac preference sync |

### Priority gaps (impact × feasibility)

1. **Triple-click client path** (if missing) — low effort, high text-edit utility.  
2. **2-finger right-click reliability** (P1-1) — already in backlog; still top UX.  
3. **Continuous pinch** — either denser Cmd+zoom pulses or accept limitation until IOKit.  
4. **Launchpad / Desktop shortcuts** as optional 4-finger or toolbar buttons.  
5. **Rotate / Notification Center / Look up** — low priority for “vibe coding + pad” core loop.  
6. **True multitouch HID** — unlocks fidelity; 5–10× engineering (architecture.md).

---

## 3) Voice STT options (pass-through only)

**Product rule**: MagicPad must **not** bind Grok/Claude/Cursor/any LLM. Voice pipeline ends at:

```
speech → text → (optional clean) → WS {"type":"voice",…} → Mac clipboard → optional Cmd+V
```

Current implementation (`MagicPadClient/index.html`): **system keyboard dictation** into a textarea, `normalizeDictationText` (e.g. `一二123456` → `123456`), then send/replace/append. No on-device recognizer, no file upload, no cloud STT API in-app.

### Option A — System dictation (status quo)

| | |
|---|---|
| **How** | Focus textarea → globe/mic on iOS keyboard → OS dictation inserts text → user sends or “直达” |
| **Pros** | Zero API keys; best Chinese/English quality on modern iPhones; privacy UI is Apple’s; works offline for downloaded languages; no extra permissions in web page beyond focus |
| **Cons** | User must open keyboard; interim results are OS-controlled; hard to show “recording” UI; Android varies; cannot run in background tab |
| **HTTP/LAN** | Text-only WS after STT — **no audio on wire** |
| **Fits constraints** | ✅ Perfect pass-through |

**Recommendation**: keep as **default and primary** path. Document “点输入框 → 键盘听写 → 发送到 Mac”.

### Option B — Web Speech API in Safari (`SpeechRecognition`)

| | |
|---|---|
| **How** | `webkitSpeechRecognition` in page (where available) |
| **Pros** | In-page mic button UX |
| **Cons** | Safari iOS support is incomplete/quirky (interim results, permissions, HTTPS expectations); often requires **secure context** — **LAN `http://` may block or degrade**; language packs inconsistent; not under our control |
| **HTTP/LAN** | Mic capture may fail on plain HTTP; STT may hit Apple/cloud depending on browser |
| **Fits constraints** | ✅ if we only put text on clipboard — but reliability risk on MagicPad’s HTTP URL |

**Recommendation**: **experiment only** behind a flag; do not replace keyboard dictation. Prefer not to depend on this for P0.

### Option C — Mac `SFSpeechRecognizer` (live or file)

| | |
|---|---|
| **How** | Phone streams audio or uploads file → Mac Speech framework → text → same paste path |
| **Pros** | Centralizes STT on Mac; can use `requiresOnDeviceRecognition` for privacy; Mac has good models; menu-bar can show mic level |
| **Cons** | Classic API: **~1 minute** recognition limit per task; network path may hit Apple servers unless on-device forced; needs **Speech Recognition + Microphone** entitlements/Info.plist strings; live streaming protocol is new surface; battery; failure modes when service throttled |
| **macOS 26 / SpeechAnalyzer** | Newer on-device-oriented APIs (SpeechAnalyzer) improve long-form transcription story on new OS — research when targeting Tahoe 26+ only |
| **HTTP/LAN** | **Audio bytes on LAN** (privacy: still local-only if no Internet, but larger attack surface). Plain HTTP uploads are snifflable on hostile Wi‑Fi — acceptable for trusted home LAN model (same as “no token” design), document clearly |
| **Fits constraints** | ✅ if output is still only clipboard paste — **no LLM** |

**Design sketch (P2-1)** — do not implement tonight:

1. Client: `MediaRecorder` → `POST /stt` multipart or WS binary chunks (cap 55s).  
2. Server: write temp file → `SFSpeechURLRecognitionRequest` **or** buffer request for live.  
3. Return `{ text }` → client fills textarea **or** server directly pastes (prefer client confirm for replace safety).  
4. Info.plist: `NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription` only if Mac captures mic (file path may skip Mac mic).  
5. Explicit UI: “转写在 Mac 本地/设备上完成，不经 MagicPad 云，不接 AI agent”.

### Option D — File upload only (phone records, Mac transcribes)

| | |
|---|---|
| **How** | Phone records m4a/webm → upload → Mac STT → text back |
| **Pros** | Clear session boundaries; easier to reason than full-duplex stream; works when live mic in Safari is blocked |
| **Cons** | Higher latency; same 1‑min SFSpeech limit unless chunked; large payloads on Wi‑Fi |
| **Fits constraints** | ✅ |

**Recommendation**: best **secondary** path if keyboard dictation fails (e.g. Android quality issues).

### Option E — Cloud STT / on-device Whisper in MagicPad

| | |
|---|---|
| **Verdict** | **Out of scope** for product defaults: API keys, vendor lock-in, and “agent-ish” perception. Self-hosted Whisper on Mac is still “compute in MagicPad” — only consider if user explicitly wants offline long-form later, still **text pass-through only**. |

### Decision matrix (summary)

| Path | Latency | LAN HTTP OK | Privacy story | Aligns w/ no-LLM | Priority |
|---|---|---|---|---|---|
| A System dictation | Best (OS) | ✅ text only | OS | ✅ | **P0 keep** |
| B Web Speech | Medium | ⚠️ often needs HTTPS | Browser | ✅ | P2 experiment |
| C Mac SFSpeech live | Medium | ⚠️ audio | On-device flag | ✅ | P2 design |
| D File → Mac STT | Higher | ⚠️ audio file | On-device flag | ✅ | P2 after C |
| Cloud STT / agent | — | — | Cloud | ❌ product | **wont** |

---

## 4) UI inspiration notes

Goals: feel like a **remote trackpad + Control Center module**, not a chat agent. Existing code already aims this way (`MagicPadServer.swift` menu bar comments; client glass CSS).

### Control Center modular

- **Tiles**: each function is a rounded rectangle with clear on/off tint (blue = live, gray = idle).  
- Mac menu bar already: hero QR + 2×2 modules — extend the same language on **iOS chrome** (mode tabs already segment-control-like).  
- Avoid deep navigation; max 2 modes primary: **触控板 | 语音**. Secondary actions as dock chips (右键, 发送, Mac⌫).  
- Status as a **thin bar**, not a modal: connected host, AX warning, latency.

### Glass / Liquid Glass (iOS 26 direction)

Apple’s **Liquid Glass** (WWDC 2025 / iOS 26): translucent material, hierarchy of controls above content, blur + refraction, morphing controls.

**MagicPad mapping (web constraints)**:

| Token | Current | Next polish |
|---|---|---|
| Background | deep `#0a0a14` + radial accents | Keep dark; avoid pure black walls |
| Glass panels | `backdrop-filter: blur(40px)` + low white alpha | Slightly stronger border luminance on focus; reduce noise gradients |
| Accent | `#6c8cff` / purple secondary | Use accent **only for active state** (CC tint rule) |
| Typography | SF system | Keep; avoid decorative display fonts on pad (repo “复古节制” is for other products — MagicPad stays system) |
| Motion | trail + haptic | Prefer short opacity/scale on press (≤150ms); no neon glow |

Do **not** fake full Liquid Glass refraction in pure CSS beyond blur/saturate — readability on outdoor iPhone > spectacle.

### Large touch targets (44pt)

Apple HIG: **minimum ~44×44 pt** interactive targets.

| Control | Guidance |
|---|---|
| Mode tabs | Already ~min-width 88px — good |
| Primary send | `min-height: 54–56px` — good; keep ≥44 on compact |
| Draft edit chips (⌫, 清空) | Ensure hit slop ≥44 even if visual glyph smaller (`padding` / `min-height`) |
| Connect button / host field | Full-width on phone; field ≥44 tall |
| Right-click FAB on pad | Large enough for thumb without occluding center of pad |
| Spacing rhythm | 8 / 12 / 16 (Mac menu bar already documents this) |

### Voice panel UX (non-agent)

- Copy must say **“发送到 Mac / 粘贴到当前输入框”**, never “问 AI”.  
- Composer is the hero; dock is secondary.  
- Recording state (if any STT added) = simple pulse dot, not waveform-as-branding spectacle.  
- Empty state: one line checklist — 键盘听写 → 发送.

### First-run / recovery (P1-5)

- First open: 3-gesture cheat sheet (move, 2-finger scroll, long-press drag).  
- Disconnect: big “重连” + show last host + link to LAN checklist (§1).

---

## Top action items (impact rank)

See response summary; mirrored here for the doc:

1. **Ship multi-device LAN reliability UX** — health, multi-IP picker, checklist on failed connect (unblocks all other features).  
2. **Stabilize 2-finger right-click** (P1-1) — core trackpad parity.  
3. **Keep system dictation; design Mac STT as optional P2** — avoid HTTPS/Web Speech rabbit hole.  
4. **Wire missing high-value gestures** (triple-click client; optional Launchpad/Desktop shortcuts as buttons).  
5. **UI pass: 44pt audit + CC modular consistency + first-run gesture sheet** — perceived quality without protocol change.

---

## Pointers

- Session log (overnight): [`SESSION-NIGHT-LOG.md`](./SESSION-NIGHT-LOG.md)  
- Architecture / inject strategy: [`architecture.md`](./architecture.md)  
- Accessibility after rebuild: [`ACCESSIBILITY.md`](./ACCESSIBILITY.md)  
- Backlog IDs: `P0-9`, `P1-1`, `P1-5`, `P2-1` in [`../BACKLOG.md`](../BACKLOG.md)
