# P2-3 原生触觉调研结论

**Date**: 2026-08-09 · **Update**: 2026-08-13 H14  
**Status**: Web trackpad mapping shipped; iPhone Safari still cannot guarantee Taptic  
**Constraint**: MagicPad client is **LAN HTTP single-file HTML** (no Xcode on this Mac; native shell sources only).

---

## Verdict

| Layer | What you get | Enough for trackpad feel? |
|---|---|---|
| **Web `navigator.vibrate`** | Coarse on/off pulse patterns (ms) | ❌ No Force Touch / semantic tick |
| **Pointer Events** | Input only | ❌ No actuators |
| **macOS `NSHapticFeedbackManager`** | Real Force Touch trackpad feedback | ✅ Only when **Mac trackpad is touched** |
| **iOS Core Haptics / UIImpactFeedback** | True phone haptics | ✅ Needs **native app / WKWebView shell** |

**Product decision**: Keep **Web vibrate helpers** as best-effort feedback on Android/some iOS. Do **not** block MagicPad on a native shell. Document true haptics as **Phase: native shell** (optional later).

---

## Why pure Web cannot match Magic Trackpad

1. Vibration API is mobile-centric on/off buzzes — not `alignment` / `levelChange` / click semantics.  
2. Safari on iOS often **ignores or heavily limits** `vibrate`.  
3. Phone screen has no Force Touch trackpad actuator; Mac Force Touch API only fires when the **local** trackpad is in contact (Apple guidance: feedback may be suppressed if not touching the trackpad).  
4. MagicPad injects CGEvent **remotely** — the phone is the input surface, so Mac trackpad haptics rarely help the phone user.

---

## Shipped in client (2026-08-09)

Semantic helpers (still `navigator.vibrate` under the hood):

| Helper | Use | Call sites (examples) |
|---|---|---|
| `hapticTap` / `hapticClick` | light confirm | UI taps |
| `hapticRight` | secondary click | 2-finger right-click + pad button |
| `hapticSelect` | double/triple select | multi-tap select path |
| `hapticSmartZoom` | pinch-adjacent | 2-finger double-tap |
| `hapticScrollArm` | crossed 2-finger scroll deadzone | **once** when `twoFingerScrollArmed` → true |
| `hapticMission` | Mission Control swipe | 3-finger swipe fire |
| `hapticSend` | voice send confirm | `sendVoiceToMac` success (instant / manual) |
| `hapticWarn` | empty / fail nudge | empty transcript send |

`CONFIG.enableHaptic` still gates all pulses.

**Hard limit**: Web **cannot** implement Apple Force Touch / trackpad `NSHapticFeedbackManager` patterns on the phone. True Core Haptics needs a native shell (future; not default product).

## 2026-08-13 H14 — closer to a real trackpad

Mapping (intentional):

| Event | Haptic | Why |
|---|---|---|
| 单指轻点 / 双击 / 三击 | click / select | 像点按 |
| 长按进入拖选 | arm（偏重） | 接近 Force Click |
| 双指右键 | right | 副点按 |
| 双指越过滚动死区 | scrollArm **一次** | 不是滚轮刻度 |
| 滑动移光标 / 连续滚动 | **不震** | 真触摸板也不会一路buzz |
| 三/四指系统手势发出 | mission | 确认 |

Backends, in order:

1. `window.MAGICPAD_HAPTIC` or `webkit.messageHandlers.magicpadHaptic`（WKWebView / 未来原生壳）
2. Hidden `<input type="checkbox" switch>` toggle（iOS 17.4–26.4 曾能骗到系统触感；**26.5+ 已补丁**，程序化 `.click()` 无效）
3. `navigator.vibrate`（Android Chrome；**iPhone Safari 从未实现**）

`CONFIG.enableHaptic` 默认 **开**（不再要求 `'vibrate' in navigator`，否则 iPhone 永远走不到 2）。`?haptic=0` 或手势页「触感：关」写入 `localStorage`.

**H16（2026-08-13）**：iOS 26.5+ 程序化 `.click()` 已失效。板面和按钮上铺一层真实 `input[switch]`（`opacity:0`，`-webkit-appearance:switch`），手指直接点到开关才会震。轻点会震，滑动通常不会触发 click。iOS 上板面不再 `preventDefault` 掉这次 click。

**H17 / H18（2026-08-13）— 全 iOS 矩阵**（不给 27 单独打补丁）

| 系统 | 后端 | 说明 |
|---|---|---|
| 非 Apple 触摸 / iOS &lt; 17.4 | none | 网页没有 Taptic；有原生壳才走 `magicpadHaptic` |
| iOS / iPadOS 17.4 – 26.4 | programmatic | 轻点手势里 `label.click()`；板上 switch `pointer-events:none`，不抢触摸 |
| iOS / iPadOS 26.5+（含 27、28…） | overlay | 手指必须点到板上的 switch；脚本点无效。滑动不震 |
| UA 解析失败 | programmatic | **不**回退 overlay，避免抢走板面手势 |

UA 只认 `iPhone OS` / `CPU OS` / `iPad OS`，以及 iPad 桌面站的 `Version/x.y`。禁止裸匹配 `OS (\d+)`（会误吃 `Mac OS X 10_15_7`）。CriOS / FxiOS 仍带 iPhone OS，走同一条。

QA：`?hapticMode=none|programmatic|overlay` 可强制路径，一台机验三条。`?haptic=0` 关触感。

不引入 pointermove 连震（那会像游戏手柄，不像触摸板）。系统设置里「系统触感」仍须打开。

本机无 Xcode.app，无法现场编 iOS 壳。桥接源码：`MagicPadIOS/HapticBridge.swift`。

---

## Minimal native path (future, out of default product)

1. **WKWebView** or **Tauri iOS** wrapper around the same HTML.  
2. Bridge: `webkit.messageHandlers.haptic.postMessage({ kind: "right" })`.  
3. Map kinds → `UIImpactFeedbackGenerator` / Core Haptics.  
4. Optional Mac menu-bar: `NSHapticFeedbackManager.defaultPerformer().perform(.generic, …)` only for local debugging.

**Not in scope**: Bluetooth HID “fake trackpad” with haptics; Continuity-coupled shells.

---

## Acceptance (P2-3)

- [x] Document that Web cannot do true trackpad haptics  
- [x] Ship semantic vibrate helpers + scroll-arm tick  
- [x] No LLM / no third-party haptic cloud  
- [ ] Native iOS shell (explicit future product decision)

---

## Sources (research)

- MDN Vibration API  
- Microsoft Edge Web Haptics explainer (maps native backends; not pure-web trackpad today)  
- Apple `NSHapticFeedbackManager` / `FeedbackPattern`  
- Apple Core Haptics (iOS)  
