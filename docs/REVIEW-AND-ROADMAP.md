# MagicPad 仓库评审 · 竞品对照 · 后续开发计划

**日期**：2026-09-15  
**范围**：GitHub `main`（`c83326e`）+ 本地工程循环 `cursor/eng-loop-895b`（`705c582`）+ 公开同类产品  
**性质**：评审与计划。本文件不改协议字节、不接 LLM、不建议公网穿透。

---

## 1. 一句话结论

MagicPad 的产品命题是对的，而且在开源同类里几乎是独一份：

> **任意手机浏览器 → 同一 Wi‑Fi 上的 Mac 菜单栏 → 触控板 + 本机 Whisper 听写。不装手机 App，不绑云端 LLM。**

工程上，**触控注入与听写主路径已经能用**；真正卡住发布的不是再写第 40 个协议锁，而是：

1. **人机分发**：本机 `705c582` 与 GitHub / [PR #1](https://github.com/Dejavu845/magicpad/pull/1) 脱节，248 个循环提交不宜原样合进 `main`。  
2. **首次成功率**：换网、访客 Wi‑Fi、自签证书、辅助功能丢勾，比再锁一条 HTTP 路由更能决定「朋友能不能用」。  
3. **可维护性**：`MagicPadClient/index.html` 约 **1.27 万行** 单文件，继续在上面叠循环会把产品改不动。

下面按「仓库现状 → 竞品 → 建议与计划」展开。

---

## 2. 产品是什么（以及故意不是什么）

| 是 | 不是 |
|---|---|
| 通用 Mac 输入外设（光标 + 文本进焦点框） | ChatGPT / Claude / Grok / Cursor 遥控 |
| 语音终点 = 剪贴板 + 可选 Cmd+V | 产品内 LLM、API key、agent |
| 局域网 HTTP `:7878` + 听写 HTTPS `:7879` | 公网 URL、ngrok、账号体系 |
| CGEvent 公开 API；`pending` / `armed` / `multi` | 用滑动距离 promote 成左键；蓝牙 / Continuity 产品路径 |

用户在 **任意** 输入框工作（备忘录、浏览器、终端、IDE）。MagicPad 只传指针和文本；写什么、问哪个 AI，由用户自己决定。这条边界必须保持——它既是隐私承诺，也是和 Wispr / Superwhisper「AI 听写」市场的错位。

---

## 3. 仓库评审

### 3.1 拓扑（仍成立）

```
手机浏览器（单文件 index.html）
  TouchEvents → 13B / 18B 小端帧 → ws://
  JSON：voice / stt / type / key / classify（遥测，不注入）
        │
        ▼  同一局域网
Mac 菜单栏 App（SwiftPM · LSUIElement）
  NWListener 手写 RFC 6455
  EventInjector → CGEventPost
  WhisperKit（base → tiny）/ 可选 Apple 本机 Speech
```

分层是清楚的：`MagicPadCore`（纯 Foundation，可在 Linux 对照） / `MagicPadServer`（AppKit + Network + CGEvent + WhisperKit） / `MagicPadClient` / `scripts/` Linux 门。这是正确的 Cloud Agent 友好切法。

### 3.2 规模（本地 `705c582`）

| 文件 | 行数 | 角色 |
|---|---:|---|
| `MagicPadClient/index.html` | 12 672 | UI + 手势 + WS + 听写 + 布局 |
| `WebSocketServer.swift` | 1 620 | HTTP/WS + Origin + 路由 |
| `EventInjector.swift` | 1 549 | 状态机与系统手势 |
| `SpeechSession.swift` | 839 | 本机 STT 生命周期 |
| `KeyProtocol.swift` | 446 | 键 / 文本 / 语音解析 |

`main` 上的 `WebSocketServer.swift` 约 **61 KB**，不是循环文档里反复写的「140 字节 stub」。那条说法已经过时，再当事实会误导合入判断。

### 3.3 做得好的地方

- **产品诚实**：文案走「听写 / Whisper 转写 / 剪贴板」，不写「AI」「一键精准」。辅助功能是四通道提示（顶栏、状态点、横幅、右键「需 AX」），不是假装已注入。  
- **手势策略对**：单指只移光标、长按才武装拖选，避免「一滑就选字」。双指滚 / 右键、三指调度中心、四指 Launchpad / 桌面，覆盖已经超过多数浏览器遥控。  
- **安全模型自洽**：产品就是「同 Wi‑Fi 未登录注入」。Origin 允许列表、POST `/stt` `/drop` 同源、配对口令默认关且 **禁止写进 QR / `/health`**，比把 token 印在二维码里的 iControl 更干净。  
- **听写落点正确**：Whisper 在 Mac（ANE），音频可以不上公网。`no_on_device_stt` 拒绝云端 Apple Speech，和 AGENTS.md 一致。  
- **换网**：`LANNetworkMonitor`，证书 SAN 自愈、QR 以当前 HTTP `:7878` 为准，比写死家里 IP 的早期版本成熟。  
- **Linux 门**：`lint-repo.sh`、`check-html.py`、协议单测、禁止烘焙 LAN IP / 家目录。Cloud Agent 能守底线。

### 3.4 主要问题

#### A. Git 与发布脱节（P0，流程）

| 树 | 状态 |
|---|---|
| `origin/main` | `c83326e` · 可用的产品快照 |
| 本地 `cursor/eng-loop-895b` | `705c582` · Cycle 1–39（协议 / Core / 测试） |
| GitHub PR #1 | draft · head `5053f96` · **248 commits** · 落后本机 |

循环把大量「classify 不是 HTTP 路由」「WS type 不是 path」锁进独立测试文件。这些锁有价值，但 **不宜 248 提交一次性合 main**。正确做法是：人在有写权限的机器上 `git push` 本机分支，再 **squash 或按主题切 2–3 个 PR**（Core 解析、协议文档、HTML a11y），不要把 cycle 日志当产品历史。

#### B. 客户端是单体（P0，可维护性）

12 k 行单文件没有 bundler、没有 CDN，这是产品约束，也是负债。手势、连接、听写、布局、玻璃皮肤挤在一起。后果：

- 改一处触感就可能碰听写或 htmlRev。  
- Linux 只能做字符串 / `node --check`，不能做真实 Touch 序列。  
- RESEARCH-NEXT 里的「失败时给人看的清单」很难安全落地。

下一步不是上 React，而是 **逻辑拆文件、运行时仍可拼成单页**（或 `build_app.sh` 内联），并给手势 / host 解析补纯 JS 单测。

#### C. 循环收益递减（P1，流程）

Cycle 32–39 基本是「某字符串不得出现在某表」。协议目录该冻了：`HTTP_ROUTES` 五条、`WSType` 八个名字、13B/18B 布局。再开循环应绑定 **用户可感知的失败**（连不上、AX 掉、Android 听写失败），而不是再锁一个否定句。

#### D. 文档漂移（P1）

`docs/RESEARCH-NEXT.md`（2026-08-08）仍把听写写成「系统键盘听写为主，Whisper 不在默认路径」。当前 README / 客户端已经是 **手机麦 → Mac Whisper**。`OPTIMIZATIONS.md` 仍写 remote 140-byte stub。新贡献者会按错地图施工。

#### E. 注入保真度上限（P2，产品诚实）

捏合是 Cmd+= / −，智能缩放是 Cmd+0，三指是调度中心快捷键。只监听 **真触控板手势** 的 App 对不齐 Magic Trackpad。这不是 bug，但菜单和指南必须继续写「近似」，不要写成「完整 Magic Trackpad」。IOKit HID 是 5–10× 工程，不应挤进近期。

#### F. 分发摩擦（P1，增长）

Ad-hoc 签名 → Gatekeeper「无法验证开发者」。全量重打包常掉辅助功能勾。Whisper 权重 80–150 MB 不进 Git（正确），但朋友拷 `.app` 时经常没有模型 → 听写直接 `no_on_device_stt`。没有公证 / Homebrew，分享仍是「U 盘 + 右键打开」。

#### G. 本环境无法关 Mac 门

Linux Cloud Agent 不能 `swift test` / `build_app.sh` / 真机扫码。`smoke-all.sh`、手势手感、HTTPS 证书墙，只能由主人 Mac 关。计划里凡标 **Mac** 的项，都不要假装 CI 已绿。

---

## 4. 同类产品调研

分两条线：手机当触控板，以及 Mac 听写。MagicPad 卡在交叉点。

### 4.1 手机 → 电脑指针 / 键盘

| 产品 | 手机侧 | 鉴权 | 听写 | 手势 / 扩展 | 和 MagicPad |
|---|---|---|---|---|---|
| **Remote Mouse** | 商店 App | 可选密码 | 手机系统语音 | 强；媒体 / 剪贴板 / 陀螺仪 | 最大商业参照。要装 App，语音走手机云/系统，不是 Mac Whisper |
| **Unified Remote** | 商店 App | 密码 + 加密 | 弱 | 上百套 App 遥控、投屏、文件 | 客厅万能遥控，不是「输入外设」 |
| **[MacPilot](https://github.com/joonlab/MacPilot)** | 浏览器 | 可选 6 位 PIN | 无 | 触控板 + 键盘 + 宏甲板 | **架构最像**：菜单栏 + 单页 + 手写 WS + CGEvent。缺听写；有咖啡馆 PIN |
| **[Fingerfly](https://github.com/narendraio/fingerfly)** | 浏览器 | 无 | 无 | 基础多指 | Python 玩具；无菜单栏产品化 |
| **[Air Keyboard](https://github.com/dendyelo/air-keyboard)** | 浏览器 | 4 位 PIN + 信任设备 | 无 | 基础触控 + 键 | PIN 默认开，值得学 |
| **[iControl](https://github.com/aianisulislam/iControl)** | 浏览器 | token **印在 QR** | 无 | 媒体 / 电源 | MagicPad 已明确拒绝「token 进二维码」 |
| **[Entangle](https://github.com/gabrieldonadel/entangle)** | iOS / Android 原生 | Bonjour | 无 | 触控 + 键 | 要上架；发现体验好，和「扫码即用」相反 |
| **Sidecar / 通用控制** | 苹果账号 + iPad | Apple ID | 无 | 真系统指针 | iPhone 不是 Sidecar 屏；不是「任意安卓浏览器」 |

商业遥控赢点：**发现、媒体甲板、跨 Windows**。开源浏览器遥控赢点：**零安装**。没有一家把 **本机 Whisper 听写** 做成和触控板同页的默认能力。

### 4.2 Mac 听写（语音 → 焦点框）

| 产品 | 模型位置 | 输入 | LLM 润色 | 和 MagicPad |
|---|---|---|---|---|
| **Superwhisper** | 本机 Whisper / 可选云 | Mac 热键麦 | 可选（BYOK） | 听写体验标杆；不是手机遥控 |
| **MacWhisper** | 本机 | 文件为主 | 事后 | 转录工具，不是触控板 |
| **Wispr Flow** | 云 | 系统级听写 | 内建 | 和「无云 LLM」相反 |
| **系统听写** | 苹果 | 键盘麦 | 无 | MagicPad 仍应保留为无 HTTPS 时的退路 |
| **MagicPad** | Mac WhisperKit | **手机麦，LAN 上传** | **禁止** | 独特：人在沙发/床上对着手机说，字进当前 Mac 焦点 |

竞品不会做成「手机当麦、Mac 算 Whisper、产品不接 agent」。不要为了追上 Superwhisper 的润色而拆掉这条边界。

### 4.3 差异化（2026-09 仍成立）

1. **零手机 App**（对 iPhone 沙盒和安卓侧载都友好）。  
2. **听写算力在 Mac**，不是手机厂商云，也不是 Wispr。  
3. **公开承诺不绑 AI**——在「一切都要接 agent」的环境里，这是定位，不是功能缺失。  
4. **协议小、可审计**：13/18 字节 + 允许列表 JSON，比「JSON 里随便发 keyCode」安全。

不要去补的：Windows 客户端、Spotify 遥控、屏幕镜像、公网。那些是 Unified Remote 的战场。

该偷的：

| 来源 | 偷什么 | 不要偷 |
|---|---|---|
| MacPilot / Air Keyboard | 菜单里一键开 PIN（默认仍可关） | 宏甲板 / Stream Deck 化 |
| Remote Mouse | 首次连接清单、剪贴板双向（若做，只文本） | 商店 App、广告、陀螺仪鼠标 |
| Entangle | Bonjour 作 **备选发现**（浏览器仍以 IP QR 为主） | 强制原生 App |
| Superwhisper | 热词 / 语言切换的克制 UI | 云润色、按 App 的 AI mode |
| iControl | — | token 进 QR |

建议、阶段计划和 Mac 核对清单见 [`REVIEW-AND-ROADMAP-PLAN.md`](REVIEW-AND-ROADMAP-PLAN.md)。
