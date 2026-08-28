# MagicPad — Android Chrome 冒烟清单（P1-6）

**Date**: 2026-08-08  
**URL**: 与 iPhone **完全相同**，例如  
`http://<mac-lan-ip>:7878/?auto=1&host=<mac-lan-ip>`  
**约束**: 同一 Wi‑Fi 非访客网；无产品 LLM；触控板 + 语音透传；协议无 Android 分支  
**Client**: `MagicPadClient/index.html`（与 iOS 同一份）

Related: [`RESEARCH-NEXT.md`](./RESEARCH-NEXT.md) §1 L

历史：Android 浏览器已完成 HTTP + WS + `hello`。

---

## 检查表（手测）

| # | 步骤 | 期望 | 结果 (手填) |
|---|---|---|---|
| 1 | 打开 `/health` | JSON `ok:true`，有 `ip`/`ips`/`html` | |
| 2 | 打开 `/` 或扫码 URL | 非空白；boot 后见连接卡或已自动连 | |
| 3 | 自动 / 手动连接 | 状态点变绿；`statusTarget` 显示 IP | |
| 4 | 「检测服务 /health」 | 卡片显示 ok；记下 `ax` | |
| 5 | 单指滑动 | Mac 光标移动；**不选中文字** | |
| 6 | 单指轻点 | 左键单击 | |
| 7 | 长按再滑 | 可拖选（armed） | |
| 8 | 双指轻点 | 右键；不稳则点「右键菜单」 | |
| 9 | 双指滑动 | 页面滚动 | |
| 10 | 底部：选段 / 实际大小 | 注入生效（需 Mac 辅助功能） | |
| 11 | 系统行：调度中心 / 桌面切换 / 启动台 | 系统级响应 | |
| 12 | 语音页：Gboard 🎙 + ⌫ 删改 | 字进 textarea；可删可改 | |
| 13 | 「发送到 Mac」 | `voice_ack`；剪贴板 + 可选粘贴（`ax:true`） | |
| 14 | 断线再恢复 | 连接卡回显；可重连 | |

---

## 与 iOS Safari 的差异

| 维度 | iOS Safari | Android Chrome / Chromium 壳 | 冒烟注意 |
|---|---|---|---|
| **打开权限** | 常弹 **本地网络**；拒则空白/WS 失败 | 一般无 iOS 式弹窗；桌面 Chrome LNA 对纯数字 LAN IP 多半可通（观察 RESEARCH-NEXT L） | 打不开先查 **同 SSID / 访客隔离 / VPN** |
| **厂商浏览器** | Safari 为主 | Chrome / MiuiBrowser / Samsung Internet / WebView | 优先 **Chrome 稳定版** |
| **触控多指** | TouchEvents 稳 | 多可用；OEM 可抢 **侧滑返回 / 三指截屏** | 略远离边缘；右键不稳用按钮 |
| **长按** | callout 已关 | 偶发选择菜单闪一下 | CSS `user-select:none`；验收用按钮 |
| **视口** | safe-area + PWA meta | 地址栏显隐；`100dvh` / visualViewport | 语音页键盘顶起后确认发送钮可点 |
| **听写** | 系统键盘 🎙 | Gboard / 厂商输入法 🎙 → 同一 `textarea` | **不依赖** Web Speech API |
| **语音协议** | `type:voice` JSON | **同一** JSON，无 Android 特判 | 验剪贴板 + Cmd+V |
| **振动** | 常无 | `navigator.vibrate` 因机而异 | 非门禁 |

协议层 **无平台分支**：同一 13B/18B 二进制帧 + 同一 voice JSON。

---

## 常见失败

| 症状 | 先查 |
|---|---|
| 超时 / 打不开 | 同 SSID、关访客隔离、数字 IP、防火墙 7878 |
| 页开了一直未连接 | `?host=` 是否可达；是否 VPN 虚拟网卡 IP |
| 已连接光标不动 | `/health` → `ax:false` → 重建后重勾辅助功能（非 Android） |
| 双指右键变返回/截屏 | OEM 系统手势 → 底部右键按钮 |
| 听写无字 | 输入法麦克风权限；换 Gboard |
| 键盘顶起点不到发送 | 滚到 dock；记机型若复现 |

---

## Mac 侧快速探测

```bash
curl -sS http://127.0.0.1:7878/health
# 手机同网: http://<mac-ip>:7878/health
# 协议冒烟见 SMOKE-NIGHT.md（与平台无关）
```

记录：2026-08-08 文档落地；真机结果待用户填。  
Alias：[`SMOKE-ANDROID.md`](./SMOKE-ANDROID.md) → 本文。
