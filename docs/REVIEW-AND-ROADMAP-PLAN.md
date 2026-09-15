# MagicPad 建议与开发计划

续篇。评审与竞品见 [`REVIEW-AND-ROADMAP.md`](REVIEW-AND-ROADMAP.md)。

---

## 5. 建议（按影响，不按循环号）

### 必须先做

1. **人推本机分支，拆开合入**  
   `git push` `cursor/eng-loop-895b`（或 squash 后的主题分支）。PR #1 保持 draft，不要当发布列车。大文件（`WebSocketServer.swift`、`index.html`、`EventInjector.swift`）走 git，不要 Contents API。

2. **冻协议，停否定句循环**  
   五条 HTTP、八个 WS type、13/18B、classify 不注入。新工作用产品 bug 单，不再 `test_cycle40_*.py`。

3. **连失败要说人话**  
   页上「已断开」应能区分：拒绝连接 / 子网不匹配 / 访客隔离 / AX 未勾 / htmlRev 过期。菜单列出 **全部私网 IP**，标明哪块是当前路由网卡。`docs/RESEARCH-NEXT.md` §1 的清单应进连接卡，而不是只躺在文档里。

4. **听写首次路径**  
   HTTP 扫码 → 页内「去 HTTPS 录音」→ 自签「继续访问」→ 证书目录入口。权重缺失时菜单直说「未下载 Whisper，触控可用」，并指向 `fetch-whisper-model.sh`，不要只回 JSON `no_on_device_stt`。

### 应该做

5. **可选 PIN（默认关）**  
   Cycle 20 的 `MAGICPAD_PAIRING_TOKEN` 已有。缺的是菜单「生成 4–6 位、显示一次、不进 QR」——咖啡馆 / 公司 Wi‑Fi 刚需。MacPilot 证明这不破坏「家用零摩擦」。

6. **Android 听写**  
   README 已写 webm 可能失败。给 webm → 本机转码或明确「请改用 m4a / 系统键盘听写」，比再锁一个 STT JSON 字段有用。

7. **拆 `index.html`**  
   建议切块：`pad-gestures.js`、`connect.js`、`voice.js`、`layout.css`。`build_app.sh` 拼回单文件以保住「无 CDN」。htmlRev 仍只对拼好的产物递增。

8. **公证或 Developer ID**  
   否则 `SHARE-APP.md` 永远是 Gatekeeper 说明书。`--html-only` 继续作为「改页不掉 AX」的主路径。

### 可以等

9. 双指右键稳态、三击选段（若客户端未稳发 phase 22）。  
10. Playwright 四视口（`phone-port` / `phone-land` / `tablet-port` / `tablet-land`）。  
11. macOS CI（`swift test` + `build_app.sh`），Linux 门保持。  
12. 可选 WKWebView 壳（仅真 Taptic）。**不要**上架成「必须装的手机 App」。  
13. IOKit 真多指 — 单独立项，不进默认路线。

### 明确不做

- 产品 LLM /「问 AI」/ 绑 Cursor  
- 公网隧道、UPnP、把 `/health` 当发现互联网的 API  
- Whisper 权重进 Git  
- 改 13B/18B 或 `pending` 因滑动变左键  
- QR 携带 `pair=` / `classify=` / 家目录 / 个人邮箱  
- 为了 Liquid Glass 牺牲户外可读性

---

## 6. 开发计划（按阶段，不按日历）

每阶段有 **可验证出口**。Linux 能关的关 Linux；标 **Mac** 的必须主人机器。

### 阶段 0 — 发布基线（流程）

**目标**：GitHub 上有一份可构建、可扫码的真实树，而不是循环叙事。

| 动作 | 出口 |
|---|---|
| 主人 Mac：`git push` 本机 `705c582`（或 squash） | `origin` 与本机同 SHA |
| 拆 PR：Core+测试 / 文档 / HTML（若 HTML 只在本机） | 每个 PR < 主题，可审 |
| 改「140-byte stub」过时句（本文件 + 后续改 `OPTIMIZATIONS.md`） | 新贡献者不再按 stub 施工 |
| 冻协议：PR 模板勾选「帧布局未改」 | 违约即拒 |

**风险**：Contents API 传大文件会截断；必须用有写权限的 git。

### 阶段 1 — 第一次连上（产品）

**目标**：换网 / 朋友机器上的失败可理解、可恢复。

| 项 | 改哪里 | 验证 |
|---|---|---|
| 连接卡：多 IP + 当前路由网卡 | 菜单 Swift + 客户端 host 选择 | **Mac** 插网线+Wi‑Fi，QR 印对手机网段 |
| 失败文案：timeout / 403 / AX / stale rev | `index.html` 连接态 | 拔网、关 AX、旧书签 三条路径 |
| 听写：HTTPS 引导 + 无权重说明 | 菜单 + 语音页 | 无 `vendor/whisper` 时触控仍可用 |
| PIN 可选 UI | 菜单；`hello.pair` 已有 | 开 PIN 后无 pair 的 hello → `pairing_rejected`；QR 仍无 `pair=` |

**不做**：Bonjour 当唯一发现；改端口默认值（7878/7879 收藏夹已形成）。

### 阶段 2 — 听写可靠（产品）

**目标**：中 / 英 / 日在 iPhone HTTPS 与一台主流安卓上可复述。

| 项 | 验证 |
|---|---|
| iPhone：自签继续访问后 `getUserMedia` → Whisper → 剪贴板 → 焦点 | **Mac + 真机** · `docs/SMOKE-DEVICE.md` |
| Android：webm 失败有退路（转码或文案） | **Mac + 真机** · `docs/ANDROID-SMOKE.md` |
| 语言切换只走 `zh-CN` / `en-US` / `ja-JP` | Linux：已有 Cycle 24；**Mac** 听一段 |

**不做**：云 STT 兜底；加「智能润色」。

### 阶段 3 — 触控手感（产品）

**目标**：日常码字 / 浏览不别扭，而不是追齐 Magic Trackpad。

| 项 | 验证 |
|---|---|
| 双指轻点右键 vs 滚动死区 | **Mac** 备忘录 + Safari |
| 三击选段（phase 22）若客户端未发则补 | 文本段选中 |
| 指南 sheet：移动 / 双指滚 / 长按拖选 | 首次打开；`?classify=0` 仍可用 |
| 文案：捏合 = 快捷键缩放 | 指南不写「真实捏合」 |

**不做**：旋转手势、Force Click、HID 描述符。

### 阶段 4 — 可维护性（工程）

**目标**：以后改手势不必读 1.2 万行。

| 项 | 出口 |
|---|---|
| 拆 JS/CSS，构建期内联 | `check-html.py` 仍过；htmlRev 规则不变 |
| 手势 / Origin / host 纯函数单测 | Linux unittest，不再堆 `test_cycleN` |
| Playwright 四视口（可选） | 按钮 ≥44px；不测真注入 |
| 主人 Mac：`swift test` + `smoke-all.sh` 写进发布检查单 | 本仓库 Linux CI 不假装已编译 App |

### 阶段 5 — 分发（增长，可选）

| 项 | 出口 |
|---|---|
| Developer ID + 公证 | 朋友双击不再绕 Gatekeeper |
| 权重下载与 `.app` 并列说明 | `SHARE-APP.md` 增加「无模型时听写不可用」 |
| Homebrew cask（公证之后） | `brew install --cask` 一条 |

仍不做公网、不做强制手机 App。

---

## 7. 建议的近期执行顺序

若只做接下来能改变「能不能用」的事，顺序如下：

```
0  人推 git + 拆合入（否则评审对象会继续分叉）
1  连接失败文案 + 多 IP 选择
2  无 Whisper 权重时的诚实空态
3  菜单 PIN（默认关）
4  Android 听写退路
5  拆客户端单文件
6  公证
```

0 不做，后面每次 Cloud Agent 都会再写一套对不齐 GitHub 的 Core 锁。

---

## 8. 给主人 Mac 的核对清单（本评审未在真机跑）

本环境无 Xcode、无手机、不能点辅助功能。下列必须在目标 Mac 上点过，才能把阶段 1–3 标完成：

```
[ ] open build/MagicPad.app 后只见菜单栏
[ ] 辅助功能勾的是当前这份 .app
[ ] 手机与 Mac 同一非访客 SSID，扫【当前】HTTP QR
[ ] 单指移动不选字；长按后拖选
[ ] 双指滚动；双指轻点出右键
[ ] HTTPS :7879 继续访问后，听写进焦点框
[ ] 去掉 Whisper 目录后再开：触控仍在，听写说明缺失模型
[ ] ./scripts/smoke-all.sh 在本机 HTTP 绿
```

---

## 9. 相关文件

- 产品边界：[`PRODUCT-DIFFERENTIATION.md`](PRODUCT-DIFFERENTIATION.md) · [`AGENTS.md`](../AGENTS.md)  
- 架构 / 协议：[`architecture.md`](architecture.md) · 本地树的 `PROTOCOL.md`  
- 换网 / 证书 / AX：[`OFF-HOME-WIFI.md`](OFF-HOME-WIFI.md) · [`RESEARCH-LAN-HTTPS.md`](RESEARCH-LAN-HTTPS.md) · [`ACCESSIBILITY.md`](ACCESSIBILITY.md)  
- 2026-08 调研（部分过时）：[`RESEARCH-NEXT.md`](RESEARCH-NEXT.md)  
- 工程循环（本地，未全部上 main）：`docs/ENGINEERING.md` · `docs/OPTIMIZATIONS.md`  
- 现有 draft PR（不要当发布）：https://github.com/Dejavu845/magicpad/pull/1
