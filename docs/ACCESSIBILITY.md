# 辅助功能（Accessibility）— P0-8

MagicPad 用 CGEvent 注入鼠标/键盘，**必须**在 macOS 辅助功能里授权。

## 路径

当前 binary（dev 包）:

```
build/MagicPad.app
```

可执行文件:

```
MagicPad.app/Contents/MacOS/MagicPadServer
```

`/health` 的 `binaryPath` 只报 `MagicPad.app`（不写家目录）。rebuild 后仍按 **这个 .app** 再勾辅助功能。

权限按 **binary 路径** 绑定。每次**全量** `build_app.sh` 重打包 / 改路径后，可能要 **重新勾选**。

只改操控页时用 `./scripts/build_app.sh --html-only`（H27）：不换 binary、不重签、不杀进程，**辅助功能勾通常还在**。手机已打开的页会在几秒内因 htmlRev 不一致自动硬刷（H11/H29）。

## 怎么开

1. 系统设置 → 隐私与安全性 → **辅助功能**  
2. 找到 **MagicPad**（或拖入 `build/MagicPad.app`）  
3. 开关打开  
4. 完全退出再开：`killall MagicPadServer` 后 `open build/MagicPad.app`  

也可菜单里触发权限提示（注入失败时会尝试 `requestAccessibilityPermission`）。

## 症状对照

| 现象 | 原因 |
|---|---|
| 光标不动 / 点不了 | 未授权或点了错 App |
| 右键无菜单 | 未授权（日志：`辅助功能未授权`） |
| 语音发了但不粘贴 | 未授权 → Cmd+V 被跳过 |
| 刚 rebuild 后全挂 | 路径变了，需重勾 |

## 日志确认

```bash
tail -f /tmp/magicpad-server.log | grep -E '辅助功能|rightClick|voice: simulated'
```

成功右键应见类似 `rightClick(ctrl+left)`；成功粘贴见 `voice: simulated Cmd+V`。

## Web page (MP-15)

The phone page is a single HTML file. Cycle 14:

- One visually-hidden `<h1>MagicPad</h1>` plus `<h2>输入</h2>` on the voice panel. The `<noscript>` heading stays inside `<noscript>`.
- Mode chrome is a `tablist` / `tab` / `tabpanel`. The pad is `role="application"`.
- `:focus-visible` outline is `#7fd1ff`.
- `user-scalable=no` is a documented exception to WCAG 1.4.4: pinch on the pad is a gesture, not page zoom. Voice textarea uses `font-size: clamp(16px, …)` so iOS does not auto-zoom on focus.
- `#voiceStatus` is `aria-live="polite"`. `#statusBar` has Enter/Space and `aria-label`.
