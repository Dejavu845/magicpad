# MagicPad 架构

**以 `AGENTS.md` 为准。** 旧稿里的 PointerEvents / 12 字节帧 / Bonjour 发现 / IOKit HID 主路径 **已过时**。

## 顶层拓扑

```
┌──────────────── iPhone / 浏览器（单文件 index.html） ────────────────┐
│  TouchEvents → 二进制帧（13B 单指 / 18B 多指）→ WebSocket            │
│  文本 JSON：voice / stt / type / key / classify（遥测，不注入）       │
└──────────────── LAN：HTTP :7878  +  HTTPS :7879 ────────────────────┘
                              ↓
┌──────────────── macOS 菜单栏 App（Swift / CGEvent） ─────────────────┐
│  WebSocketServer  NWListener                                         │
│  EventInjector    CGEvent 公开 API（禁止因滑动距离 promote 左键）     │
│  LANCert          自签 SAN；换网自愈                                 │
│  SpeechSession    SFSpeech（无 LLM）                                 │
└──────────────────────────────────────────────────────────────────────┘
```

## 协议

| 长度 | 用途 |
|---|---|
| 13 B | 单指：phase / dx / dy / pressure / buttons / t_ms / seq |
| 18 B | 多指：+ fingers / gesture / ext（pinch scale×1000 等） |

| phase | 含义 | Mac |
|---|---|---|
| 0–3 | down / move / up / cancel | mouseMoved；仅 armed 才 leftDown |
| 10 | 双击 | 两轮 down+up |
| 11 | 右键 | Control+左键 |
| 20 | 滚轮 | scrollWheel |
| 21 | 捏合 | Cmd+= / Cmd+- |
| 22 | 三击 | 三轮 down+up |
| 23 | 智能缩放 | Cmd+0 |
| 24 | Mission Control / 桌面 | Ctrl+方向 |

状态机：**pending**（只移光标）→ **armed**（长按 ~280ms 且抖 ≤14px）→ **multi**（双指+）。  
禁止用滑动距离把 pending promote 成左键。

## 注入：CGEvent，不是 HID

| | CGEventPost | IOKit HID |
|---|---|---|
| 权限 | 辅助功能 | 辅助功能 + 输入监控 |
| 三指上下 | 打开 Mission Control.app / 参数 2（不靠 Ctrl+↑） | 真 multitouch 描述符 |
| 三指左右切桌面 | 热键开：Ctrl+Arrow；热键关：调度中心+方向+回车 | 真 Spaces API |
| **现状** | ✅ | 不做（产品不做蓝牙/Continuity） |

## 客户端

- 单文件、无依赖、**TouchEvents**（PointerEvents 多指不稳，已弃）
- 主机：`location.hostname`；忽略陈旧 `?host=`
- 双指阈值：`CONFIG.twoFinger`；URL `?scrollDz&pinchMin&rightMs&pathW&commitEx&commitPx`
- 分类 HUD：松手显示 right / scroll / pinch / reject；`?classify=0` 关闭
- 触感：单击/长按/右键；滑动不震；`?haptic=0` 可关。iPhone Safari 无 `vibrate`，26.5+ 网页骗触感已失效；真 Taptic 要 WKWebView 壳（`MagicPadIOS/HapticBridge.swift`）

## 延迟预算（未变）

触摸采样 + 编码 + LAN + 解码 + CGEvent ≈ **13–20ms** 目标。不要再包一层 `requestAnimationFrame` 过滤路径。同帧**第一包立刻发**，其余仍走现有 rAF 合并（不是新过滤器）。录音贴进焦点用 **mp4**（AAC-in-MP4），不先等转写。

指针 / 滚动 / 点击 / 粘贴走 `InjectRuntime`（`userInteractive` 串行队列），**不经 MainActor**。延迟 echo 在 WS 收包线程立刻回。键与鼠标同一队列，避免 `leftButtonDown` 竞态。

## 安全

- 只听局域网；无账号；无 Internet 出口
- 网页麦必须 HTTPS :7879（自签）
- 凭证不进仓库
- 产品不接任何 LLM / agent API
