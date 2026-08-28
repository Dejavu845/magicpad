# LAN HTTPS（自签）— iPhone 网页麦克风

**Date**: 2026-08-10  
**Status**: shipped MVP (dual port)  
**Ports**: HTTP `7878` (smoke / 默认) · HTTPS `7879` (secure context / 网页录音)

---

## Why

Safari / Chrome on iOS treat **HTTP LAN pages as insecure**.  
`getUserMedia({ audio: true })` often fails unless:

1. **Secure context** (`https:` or localhost), and  
2. User grants mic permission.

MagicPad stays LAN-only (no public CA). Solution: **self-signed TLS on :7879** while keeping **plain HTTP on :7878** for scripts and simple open.

---

## What shipped

| Piece | Behavior |
|---|---|
| `LANCert.swift` | OpenSSL generate PEM+P12 under `~/Library/Application Support/MagicPad/`; **self-heal**: if primary LAN IP missing from SAN → delete p12/pem/cer + regen + log |
| Dual `NWListener` | HTTP 7878 + TLS 7879 share same HTTP/WS handlers |
| `/health` | `https`, `httpsPort`, `httpPort`, `httpsUrl`, `httpsError` |
| Client | `wss://` when page is HTTPS; same-origin POST `/stt` `/drop` |
| Menu | 「复制地址」优先 HTTPS（麦）；状态条 HTTP + HTTPS |
| UI tip | HTTP 页顶部提示切到 HTTPS :7879 |

---

## Phone steps

1. Open `https://<Mac-IP>:7879/` (menu copy or tip link).  
2. Safari: **显示详细信息 → 访问此网站** (trust self-signed once per session / device).  
3. Optional: install `magicpad-lan.cer` from Application Support for full trust (Settings → Profile → Certificate Trust).  
4. Hard-refresh pad page; try **录音发Mac**.

Fallback if still no mic: **Mac听写** / 系统听写 / 选文件上传.

---

## Constraints

- No product LLM  
- No Continuity / Bluetooth product path  
- HTTP smoke (`smoke-all.sh`) remains on `:7878`  
- Cert SAN includes localhost + current private IPs at generation time  
- **Self-heal (H1-1)**: on start, if primary private IP ∉ SAN → delete p12/pem/cer, regenerate, log `regen`  
- Menu: **打开证书目录** → `LANCert.supportDir`  
- Smoke: `scripts/smoke-https.py`; `smoke-all.sh` isolates HTTPS (WARN only, HTTP still PASS)

---

## Residual

- iOS may still prompt / block until user accepts cert  
- Self-heal runs at ensureIdentity (app start / HTTPS listener attach); mid-session IP change needs restart  
- True Core Haptics still needs native shell (`RESEARCH-HAPTICS.md`)

## macOS 钥匙串弹窗（Imported Private Key）

**原因**：HTTPS 自签 PKCS#12 的**私钥**被 `SecPKCS12Import` 放进**登录钥匙串**；TLS 握手签名时系统要授权 MagicPad 用这把钥匙。  
**不是**钓鱼、**不是**辅助功能、**不是** HTTP 触控必需。

**你怎么点**：
- 推荐点一次 **始终允许** → 以后不弹  
- 点 **允许** → 本会话可用  
- 点 **拒绝** → HTTPS:7879 可能失败；**HTTP:7878 触控板仍可用**

代码侧已给当前 App 设 ACL，新导入尽量免密；旧的 “Imported Private Key” 可能仍要点一次始终允许。
