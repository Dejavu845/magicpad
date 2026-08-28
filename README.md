# MagicPad

把 iPhone / Android / 任意浏览器变成 Mac 的虚拟触控板，再加上机 Whisper 听写。

无需安装手机 App，无需登录，扫码就连。语音只进剪贴板（可选自动 Cmd+V 到当前焦点），**不内置 LLM，不绑任何 AI agent**。

```
手机浏览器  ──LAN WebSocket──►  Mac 菜单栏 App
触摸板 / 听写 / 改焦点框          CGEvent + 本机 Whisper (ANE)
HTTP :7878 · 听写需 HTTPS :7879
```

## 特性

- 菜单栏常驻，不抢焦点、不进 Dock
- 扫码连接，同一 Wi‑Fi 即可
- 触摸板：轻触 / 点击 / 长按拖选 / 多指手势
- 听写：手机麦 → Mac 上 OpenAI Whisper Core ML（优先 **base**，tiny 兜底）
- 草稿在手机上改，Mac⌫ / 清空改电脑焦点框
- MIT 开源

## 要求

- macOS 13+（辅助功能权限）
- 手机与 Mac 同一局域网
- iPhone 听写必须打开 **HTTPS** 页（自签证书：继续访问）
- Whisper 权重不进 Git（约 80–150MB），见下方

## 快速开始

```bash
git clone https://github.com/Dejavu845/magicpad.git
cd magicpad
# 可选：先下权重（国内默认走 hf-mirror）
./scripts/fetch-whisper-model.sh
cd MagicPadServer && nice -n 19 swift build
cd ..
./scripts/build_app.sh
open build/MagicPad.app
```

首次运行：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 MagicPad。

手机打开菜单栏二维码里的地址，或：

- 触控板：`http://<Mac-LAN-IP>:7878/`
- 听写：`https://<Mac-LAN-IP>:7879/`（自签，点继续访问）

只换网页、不重签 App：`./scripts/build_app.sh --html-only`（避免辅助功能勾选掉线）。

## Whisper 权重

`vendor/whisper/` 已 gitignore。运行时也可缓存在 Application Support。完整目录需含：

`MelSpectrogram.mlmodelc` · `AudioEncoder.mlmodelc` · `TextDecoder.mlmodelc` · `tokenizer.json`

有 base 用 base，否则回退 tiny。不要把权重推进 GitHub。

## 架构

见 [`docs/architecture.md`](docs/architecture.md)。

- 客户端：`MagicPadClient/index.html`（单文件）
- 服务端：`MagicPadServer/`（SwiftPM + WhisperKit）
- 打包：`scripts/build_app.sh` → `build/MagicPad.app`

协议：13 字节单指 / 18 字节多指，小端。文本 JSON 走 voice / stt / type / key。

## 发给别人

对方必须在**自己的 Mac**上跑这份 App，手机连**那台 Mac**的 Wi‑Fi。没有公网穿透。详见 [`docs/SHARE-APP.md`](docs/SHARE-APP.md)。

## 已知限制

- 听写：iPhone 用 mp4/m4a；Android webm 可能失败
- 改电脑焦点、粘贴都要开辅助功能
- 换网后二维码会变，扫菜单栏里当前的码

## License

MIT © 2026 DJ (Dejavu)
